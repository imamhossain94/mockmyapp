/// The analysis with no model at all: the fallback on Windows, Linux, most
/// Android phones, browsers without built-in AI — and in every test.
///
/// Not a language model and not pretending to be one; the wizard labels it as
/// built-in suggestions. What it does is read the user's own description the
/// way a copywriter would skim it: the sentence that names the app, the
/// clauses that say what it does, the words that come up again and again, and
/// the vocabulary that gives away what kind of app it is. Deterministic, so
/// "Re-analyze" after an edit is a real comparison.
library;

import '../../data/services/on_device_ai.dart';
import '../models/screen_template.dart';
import 'listing_analysis.dart';

/// [description] read into a full analysis with [planLength] screens.
///
/// [appName] wins when given; otherwise one is derived from the description.
ListingAnalysis heuristicAnalysis(
  String description, {
  String appName = '',
  int planLength = kDefaultPlanLength,
}) {
  final text = description.replaceAll(RegExp(r'\s+'), ' ').trim();
  final clauses = _clauses(description);
  final name = appName.trim().isNotEmpty
      ? appName.trim()
      : deriveAppName(description);
  final nameWords = _words(name).toSet();

  final category = guessCategory('$name $text');
  final head = _headNoun[category]!;

  final features = _features(clauses, nameWords, head, category);
  final keywords = _keywords(clauses, name, nameWords, head, category);
  final usps = _usps(clauses, features, category);
  final plan = planFrom(features, usps, category, length: planLength);

  return ListingAnalysis(
    appName: name,
    category: category,
    audience: audienceFor(category, keywords),
    features: features,
    usps: usps,
    keywords: keywords,
    plan: plan,
    engine: AiEngine.phrasebook,
  ).rescored(description);
}

// -----------------------------------------------------------------------------
// Words
// -----------------------------------------------------------------------------

/// Function words and filler that never make a keyword or a feature.
const _stopwords = {
  'a',
  'an',
  'the',
  'and',
  'or',
  'but',
  'if',
  'then',
  'so',
  'than',
  'that',
  'this',
  'these',
  'those',
  'it',
  'its',
  "it's",
  'is',
  'are',
  'was',
  'were',
  'be',
  'been',
  'being',
  'am',
  'do',
  'does',
  'did',
  'done',
  'have',
  'has',
  'had',
  'of',
  'to',
  'in',
  'on',
  'at',
  'by',
  'for',
  'with',
  'from',
  'into',
  'onto',
  'out',
  'up',
  'down',
  'over',
  'under',
  'about',
  'as',
  'all',
  'any',
  'each',
  'every',
  'some',
  'more',
  'most',
  'much',
  'many',
  'very',
  'really',
  'just',
  'also',
  'too',
  'can',
  'could',
  'will',
  'would',
  'should',
  'may',
  'might',
  'must',
  'shall',
  'you',
  'your',
  "you're",
  'yours',
  'we',
  'our',
  'us',
  'they',
  'their',
  'them',
  'he',
  'she',
  'his',
  'her',
  'i',
  'me',
  'my',
  'mine',
  'who',
  'whom',
  'which',
  'what',
  'when',
  'where',
  'why',
  'how',
  'not',
  'no',
  'yes',
  'there',
  'here',
  'via',
  'per',
  'while',
  'without',
  'within',
  'across',
  'again',
  'ever',
  'never',
  'one',
  'own',
  'other',
  'such',
  'only',
  'both',
  'either',
  'neither',
  'let',
  'lets',
  'helps',
  'help',
  'using',
  'use',
  'uses',
  'used',
  'way',
  'ways',
  'thing',
  'things',
  'app',
  'apps',
  'application',
  'new',
  'best',
  'great',
  'good',
  'free',
  'now',
  'get',
  'got',
  'like',
  'even',
  'well',
  'etc',
  'off',
  'around',
  'through',
  'after',
  'before',
  'because',
  'until',
  'between',
};

/// Words too generic to stand alone as a keyword.
const _generic = {
  'screen',
  'screens',
  'feature',
  'features',
  'option',
  'options',
  'user',
  'users',
  'people',
  'everyone',
  'time',
  'times',
  'day',
  'days',
  'easy',
  'simple',
  'fast',
  'quick',
  'phone',
  'device',
  'android',
  'iphone',
  'ios',
  'mobile',
  'version',
  'update',
  'support',
  'available',
  'game',
  'games',
};

List<String> _words(String s) => RegExp(
  r"[a-z0-9][a-z0-9'+-]*",
).allMatches(s.toLowerCase()).map((m) => m.group(0)!).toList();

bool _content(String w) => w.length > 2 && !_stopwords.contains(w);

/// A word's dictionary form, near enough to count "songs" and "song" as one.
String _stem(String w) {
  if (w.length > 4 && w.endsWith('ies')) {
    return '${w.substring(0, w.length - 3)}y';
  }
  if (w.length > 3 && w.endsWith('s') && !w.endsWith('ss')) {
    return w.substring(0, w.length - 1);
  }
  return w;
}

/// The description broken into sentences and the clauses inside them.
///
/// Bullets and line breaks end a clause just as a full stop does: feature
/// lists are pasted in as lists far more often than as prose.
List<String> _clauses(String description) {
  final out = <String>[];
  for (final raw in description.split(
    RegExp(r'[\n\r]+|(?<=[.!?;])\s+|[.!?;]+$'),
  )) {
    var line = raw.trim().replaceFirst(RegExp(r'^([-*•–—]|\d+[.)])\s*'), '');
    line = line.replaceAll(RegExp(r'[.!?;:]+$'), '').trim();
    if (line.isEmpty) continue;
    // A long sentence is several claims; split it where a list would.
    final parts = _words(line).length > 14
        ? line.split(RegExp(r',\s+|\s+[-–—]\s+'))
        : [line];
    for (final part in parts) {
      final t = part.trim();
      if (t.isNotEmpty) out.add(t);
    }
  }
  return out;
}

/// The app's name, read off the description when the user gave none.
///
/// A short opening sentence — "Arrow rush game." — is a name with the kind of
/// app after it. A long one that opens on a capitalised word — "Budgetly helps
/// you…" — names the app in its first words. Anything else gets the most
/// telling words in the description, title-cased.
String deriveAppName(String description) {
  final clauses = _clauses(description);
  if (clauses.isEmpty) return '';
  final first = clauses.first;
  final words = first.split(RegExp(r'\s+'));

  // "Arrow rush game", "Sonary – music player for Android"
  final short = first.split(RegExp(r'\s+[-–—:|]\s+|:\s+')).first.trim();
  final shortWords = short.split(RegExp(r'\s+'));
  if (shortWords.length <= 5) {
    final kept = [...shortWords];
    while (kept.length > 1 && _trailingKind.contains(kept.last.toLowerCase())) {
      kept.removeLast();
    }
    if (kept.length < shortWords.length || shortWords.length <= 3) {
      final name = kept.join(' ').replaceAll(RegExp(r'[^\w\s&+-]'), '');
      if (name.trim().isNotEmpty) return _titleCase(name.trim());
    }
  }

  // "Budgetly helps you track every expense"
  final leading = <String>[];
  for (final w in words) {
    final clean = w.replaceAll(RegExp(r'[^\w&+-]'), '');
    if (clean.isEmpty || clean[0] != clean[0].toUpperCase()) break;
    if (RegExp(r'^\d').hasMatch(clean)) break;
    final lower = clean.toLowerCase();
    if (leading.isEmpty &&
        (_stopwords.contains(lower) || kBenefitVerbs.contains(lower))) {
      break;
    }
    leading.add(clean);
    if (leading.length == 3) break;
  }
  if (leading.isNotEmpty) return leading.join(' ');

  // Nothing name-like: the description's two most telling words.
  final counts = <String, int>{};
  for (final w in _words(description).where(_content)) {
    if (_generic.contains(w)) continue;
    counts[w] = (counts[w] ?? 0) + 1;
  }
  final top = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return _titleCase(top.take(2).map((e) => e.key).join(' '));
}

/// What follows a name in a short opening line — "Arrow Rush *game*".
const _trailingKind = {
  'game',
  'games',
  'app',
  'application',
  'for',
  'android',
  'ios',
  'iphone',
  'player',
  'tool',
  'the',
  'a',
  'an',
};

// -----------------------------------------------------------------------------
// Category
// -----------------------------------------------------------------------------

/// The words that give away each kind of app. The first list counts three
/// times as much as the second: "game" settles it, "level" merely suggests.
const _vocabulary = <TemplateCategory, (List<String>, List<String>)>{
  TemplateCategory.games: (
    ['game', 'gaming', 'arcade', 'puzzle', 'gamer'],
    [
      'level',
      'player',
      'score',
      'boss',
      'quest',
      'rpg',
      'shooter',
      'race',
      'racing',
      'casual',
      'multiplayer',
      'coin',
      'strategy',
      'adventure',
      'runner',
      'jump',
      'tap',
      'arrow',
      'escape',
      'challenge',
      'brain',
      'trivia',
      'play',
      'win',
      'enemy',
      'battle',
      'hero',
    ],
  ),
  TemplateCategory.music: (
    ['music', 'song', 'audio', 'playlist', 'mp3'],
    [
      'album',
      'artist',
      'radio',
      'lyric',
      'beat',
      'karaoke',
      'sound',
      'equalizer',
      'listen',
      'listening',
      'tune',
      'melody',
      'guitar',
      'piano',
      'dj',
      'track',
      'offline',
      'player',
      'podcast',
    ],
  ),
  TemplateCategory.finance: (
    ['budget', 'expense', 'finance', 'money', 'banking'],
    [
      'bank',
      'invest',
      'investing',
      'investment',
      'stock',
      'crypto',
      'saving',
      'spend',
      'spending',
      'bill',
      'tax',
      'wallet',
      'payment',
      'loan',
      'debt',
      'income',
      'salary',
      'accounting',
      'currency',
      'financial',
      'cash',
    ],
  ),
  TemplateCategory.shopping: (
    ['shop', 'shopping', 'deal', 'coupon', 'marketplace'],
    [
      'cart',
      'buy',
      'order',
      'product',
      'fashion',
      'discount',
      'sale',
      'checkout',
      'brand',
      'price',
      'store',
      'seller',
      'wishlist',
    ],
  ),
  TemplateCategory.food: (
    ['recipe', 'food', 'cooking', 'restaurant', 'meal'],
    [
      'cook',
      'dish',
      'kitchen',
      'grocery',
      'menu',
      'drink',
      'coffee',
      'bake',
      'baking',
      'chef',
      'ingredient',
      'dinner',
      'lunch',
      'breakfast',
      'diet',
    ],
  ),
  TemplateCategory.travel: (
    ['travel', 'trip', 'flight', 'hotel', 'navigation'],
    [
      'booking',
      'vacation',
      'holiday',
      'map',
      'route',
      'navigate',
      'gps',
      'commute',
      'transit',
      'bus',
      'train',
      'taxi',
      'ride',
      'tour',
      'destination',
      'itinerary',
      'traffic',
      'city',
      'airport',
    ],
  ),
  TemplateCategory.health: (
    ['fitness', 'workout', 'health', 'meditation', 'yoga'],
    [
      'exercise',
      'gym',
      'run',
      'running',
      'step',
      'calorie',
      'diet',
      'weight',
      'sleep',
      'meditate',
      'mindfulness',
      'heart',
      'wellness',
      'training',
      'hydration',
      'water',
      'period',
      'symptom',
      'doctor',
      'medication',
    ],
  ),
  TemplateCategory.education: (
    ['learn', 'learning', 'course', 'study', 'education'],
    [
      'lesson',
      'quiz',
      'school',
      'student',
      'teacher',
      'language',
      'vocabulary',
      'exam',
      'flashcard',
      'math',
      'tutor',
      'homework',
      'class',
      'kid',
      'grammar',
      'skill',
      'practice',
    ],
  ),
  TemplateCategory.entertainment: (
    ['movie', 'streaming', 'entertainment', 'anime', 'tv'],
    [
      'stream',
      'watch',
      'show',
      'series',
      'comic',
      'fun',
      'joke',
      'meme',
      'celebrity',
      'entertaining',
      'episode',
      'film',
      'cinema',
    ],
  ),
  TemplateCategory.photoVideo: (
    ['photo', 'camera', 'video', 'selfie', 'collage'],
    [
      'picture',
      'edit',
      'editor',
      'editing',
      'filter',
      'gallery',
      'image',
      'reel',
      'montage',
      'retouch',
      'portrait',
      'clip',
      'sticker',
    ],
  ),
  TemplateCategory.social: (
    ['social', 'chat', 'messaging', 'dating', 'community'],
    [
      'friend',
      'message',
      'share',
      'sharing',
      'follow',
      'follower',
      'post',
      'connect',
      'profile',
      'group',
      'feed',
      'meet',
      'match',
      'story',
    ],
  ),
  TemplateCategory.productivity: (
    ['productivity', 'todo', 'task', 'note', 'planner'],
    [
      'notebook',
      'calendar',
      'schedule',
      'reminder',
      'organize',
      'organise',
      'plan',
      'project',
      'focus',
      'habit',
      'list',
      'document',
      'pdf',
      'sync',
      'timer',
      'goal',
      'deadline',
    ],
  ),
  TemplateCategory.lifestyle: (
    ['lifestyle', 'couple', 'relationship', 'wallpaper', 'horoscope'],
    [
      'love',
      'widget',
      'astrology',
      'journal',
      'diary',
      'family',
      'pet',
      'garden',
      'beauty',
      'makeup',
      'decor',
      'quote',
      'partner',
      'home',
    ],
  ),
  TemplateCategory.business: (
    ['business', 'crm', 'invoice', 'enterprise', 'b2b'],
    [
      'team',
      'client',
      'customer',
      'sales',
      'meeting',
      'office',
      'employee',
      'workflow',
      'marketing',
      'analytics',
      'startup',
      'manager',
      'payroll',
      'lead',
      'report',
    ],
  ),
  TemplateCategory.utilities: (
    ['utility', 'cleaner', 'downloader', 'vpn', 'scanner'],
    [
      'tool',
      'battery',
      'storage',
      'file',
      'download',
      'saver',
      'flashlight',
      'qr',
      'calculator',
      'converter',
      'clock',
      'alarm',
      'weather',
      'keyboard',
      'launcher',
      'backup',
      'gesture',
      'wifi',
      'bluetooth',
      'translate',
      'translator',
      'volume',
      'control',
    ],
  ),
};

/// The kind of app [text] describes; productivity when nothing gives it away.
TemplateCategory guessCategory(String text) {
  final stems = _words(text).map(_stem).toList();
  var best = TemplateCategory.productivity;
  var bestScore = 0;
  // In enum order, and only a strictly higher score takes over, so a tie
  // always goes the same way.
  for (final category in TemplateCategory.values) {
    final (strong, weak) = _vocabulary[category]!;
    var score = 0;
    for (final w in stems) {
      if (strong.contains(w)) score += 3;
      if (weak.contains(w)) score += 1;
    }
    if (score > bestScore) {
      best = category;
      bestScore = score;
    }
  }
  return best;
}

/// The noun a store search pairs with a word for each kind of app — "escape
/// *game*", "budget *app*".
const _headNoun = <TemplateCategory, String>{
  TemplateCategory.social: 'app',
  TemplateCategory.productivity: 'app',
  TemplateCategory.finance: 'app',
  TemplateCategory.shopping: 'app',
  TemplateCategory.food: 'app',
  TemplateCategory.travel: 'app',
  TemplateCategory.health: 'app',
  TemplateCategory.education: 'app',
  TemplateCategory.entertainment: 'app',
  TemplateCategory.music: 'player',
  TemplateCategory.photoVideo: 'editor',
  TemplateCategory.games: 'game',
  TemplateCategory.lifestyle: 'app',
  TemplateCategory.business: 'app',
  TemplateCategory.utilities: 'app',
};

/// Who an app of [category] is for, as one sentence.
String audienceFor(TemplateCategory category, List<String> keywords) {
  return switch (category) {
    TemplateCategory.games =>
      'Casual mobile gamers who want a quick, entertaining challenge they can '
          'pick up anywhere.',
    TemplateCategory.music =>
      'Music lovers who want to listen to, discover and organise their '
          'favourite songs.',
    TemplateCategory.finance =>
      'People who want a clear picture of their money and to spend and save '
          'with confidence.',
    TemplateCategory.shopping =>
      'Shoppers looking for the right product at the right price, fast.',
    TemplateCategory.food =>
      'Home cooks and food lovers deciding what to eat next.',
    TemplateCategory.travel =>
      'Travellers and commuters who want to get where they are going without '
          'the hassle.',
    TemplateCategory.health =>
      'People building healthier habits who want to see their progress.',
    TemplateCategory.education =>
      'Learners of every level who want to build a skill a little every day.',
    TemplateCategory.entertainment =>
      'Anyone looking for something fun to watch, read or enjoy in a spare '
          'moment.',
    TemplateCategory.photoVideo =>
      'Creators who want their photos and videos to look their best before '
          'they share them.',
    TemplateCategory.social =>
      'People who want to stay close to friends and find their community.',
    TemplateCategory.productivity =>
      'Busy people who want to stay organised and get more done.',
    TemplateCategory.lifestyle =>
      'People who want small, personal touches that make every day better.',
    TemplateCategory.business =>
      'Professionals and small teams who want work to run smoothly.',
    TemplateCategory.utilities =>
      'Everyday phone users who want a reliable tool that just works'
          '${keywords.isEmpty ? '' : ' for ${keywords.first}'}.',
  };
}

// -----------------------------------------------------------------------------
// Features, keywords, USPs
// -----------------------------------------------------------------------------

/// The informative clauses, best first, as features.
List<ListingFeature> _features(
  List<String> clauses,
  Set<String> nameWords,
  String head,
  TemplateCategory category,
) {
  final scored = <(String, double, int)>[];
  for (final (i, clause) in clauses.indexed) {
    final words = _words(clause);
    final content = words
        .where(_content)
        .where(
          (w) => !nameWords.contains(w) && w != head && !_generic.contains(w),
        )
        .toList();
    // A clause that only restates the name ("Arrow rush game") sells nothing.
    if (content.isEmpty || words.length < 2) continue;
    final defines =
        nameWords.isNotEmpty &&
        nameWords.contains(words.first) &&
        words.length > 2 &&
        RegExp(r'\b(is|are)\s+(a|an|the)\b').hasMatch(clause.toLowerCase());
    if (defines) continue;
    var score = content.length.clamp(0, 8).toDouble();
    if (kBenefitVerbs.contains(words.first) ||
        words.take(3).any(kBenefitVerbs.contains)) {
      score += 3;
    }
    if (RegExp(r'\d').hasMatch(clause)) score += 1;
    if (words.length > 20) score -= 2;
    scored.add((clause, score, i));
  }
  // Best first, then in the order the user wrote them.
  scored.sort((a, b) {
    final byScore = b.$2.compareTo(a.$2);
    return byScore != 0 ? byScore : a.$3.compareTo(b.$3);
  });

  final features = <ListingFeature>[];
  final seen = <String>{};
  for (final (rank, (clause, _, _)) in scored.indexed) {
    final title = _titleFrom(clause);
    if (title.isEmpty || !seen.add(title.toLowerCase())) continue;
    features.add(
      ListingFeature(
        title: title,
        detail: _sentence(clause),
        importance: (10 - rank).clamp(5, 10),
      ),
    );
    if (features.length == kMaxFeatures) break;
  }
  for (final fallback in _fallbackFor(category)) {
    if (features.length >= kMinFeatures) break;
    if (seen.add(fallback.title.toLowerCase())) features.add(fallback);
  }
  return features;
}

/// Features any app of a kind can honestly claim, for a description too short
/// to supply three of its own. Every one of them is editable, and the wizard
/// says so.
const _fallbackFeatures = <TemplateCategory, List<ListingFeature>>{
  TemplateCategory.games: [
    ListingFeature(
      title: 'Quick to Pick Up',
      detail: 'Learn the rules in seconds and start playing.',
      importance: 6,
    ),
    ListingFeature(
      title: 'Hours of Fun',
      detail: 'Every round is a fresh challenge.',
      importance: 6,
    ),
    ListingFeature(
      title: 'Beat Your Best Score',
      detail: 'Come back and beat your best run.',
      importance: 5,
    ),
  ],
  TemplateCategory.music: [
    ListingFeature(
      title: 'All Your Music',
      detail: 'Every song in one place.',
      importance: 6,
    ),
    ListingFeature(
      title: 'Playlists Made Easy',
      detail: 'Build the right mix for every moment.',
      importance: 6,
    ),
    ListingFeature(
      title: 'Listen Your Way',
      detail: 'Your music, the way you like it.',
      importance: 5,
    ),
  ],
};

/// The generic three, for kinds of app without their own.
const _genericFeatures = [
  ListingFeature(
    title: 'Simple by Design',
    detail: 'Everything you need, nothing you do not.',
    importance: 6,
  ),
  ListingFeature(
    title: 'Ready in Seconds',
    detail: 'Open the app and get going straight away.',
    importance: 6,
  ),
  ListingFeature(
    title: 'Made for Every Day',
    detail: 'Fits into your routine without getting in the way.',
    importance: 5,
  ),
];

List<ListingFeature> _fallbackFor(TemplateCategory category) =>
    _fallbackFeatures[category] ?? _genericFeatures;

/// Search terms: the name, the description's own phrases, the words it keeps
/// coming back to, and those words paired with what kind of app this is.
List<String> _keywords(
  List<String> clauses,
  String name,
  Set<String> nameWords,
  String head,
  TemplateCategory category,
) {
  final out = <String>[];
  void add(String k) {
    final t = k.trim().toLowerCase();
    if (t.isEmpty || out.contains(t)) return;
    out.add(t);
  }

  if (name.trim().isNotEmpty) add(name);

  // Frequencies, and where each word first appears, for stable ordering.
  final counts = <String, int>{};
  final firstSeen = <String, int>{};
  final bigrams = <String, int>{};
  var position = 0;
  for (final clause in clauses) {
    final words = _words(clause);
    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      position++;
      if (!_content(w)) continue;
      counts[w] = (counts[w] ?? 0) + 1;
      firstSeen.putIfAbsent(w, () => position);
      if (i + 1 < words.length && _content(words[i + 1])) {
        final pair = '$w ${words[i + 1]}';
        // A pair made only of the name and the kind of app restates the name.
        final restates = pair
            .split(' ')
            .every((p) => nameWords.contains(p) || p == head);
        if (!restates) bigrams[pair] = (bigrams[pair] ?? 0) + 1;
      }
    }
  }
  int byWeight(String a, String b) {
    final byCount = (counts[b] ?? 0).compareTo(counts[a] ?? 0);
    return byCount != 0
        ? byCount
        : (firstSeen[a] ?? 0).compareTo(firstSeen[b] ?? 0);
  }

  final singles =
      counts.keys
          .where((w) => !_generic.contains(w) && w != head && w.length > 3)
          .toList()
        ..sort(byWeight);

  // Words the name does not already cover first: they reach new searches.
  final pairable = [
    ...singles.where((w) => !nameWords.contains(w)),
    ...singles.where(nameWords.contains),
  ].where((w) => _belongs(w, category));
  for (final w in pairable.take(1)) {
    add('$w $head');
  }

  final pairs = bigrams.keys.toList()
    ..sort((a, b) => (bigrams[b]!).compareTo(bigrams[a]!));
  for (final pair in pairs.take(4)) {
    add(pair);
  }
  for (final w in pairable.skip(1).take(2)) {
    add('$w $head');
  }
  for (final w in singles.take(5)) {
    add(w);
  }
  return out.take(10).toList();
}

/// Whether [word] is part of [category]'s own vocabulary — the only words
/// worth pairing with its head noun. "Escape game" is a search; "favourite
/// player" is not.
bool _belongs(String word, TemplateCategory category) {
  final (strong, weak) = _vocabulary[category]!;
  final stem = _stem(word);
  // A plural ("songs player") or, outside games, a verb ("listen player")
  // pairs into a phrase nobody types.
  if (stem != word) return false;
  if (category != TemplateCategory.games && kBenefitVerbs.contains(word)) {
    return false;
  }
  return strong.contains(stem) || weak.contains(stem);
}

/// What sets the app apart: the clauses that say so, or the strongest
/// features, as short phrases.
List<String> _usps(
  List<String> clauses,
  List<ListingFeature> features,
  TemplateCategory category,
) {
  final out = <String>[];
  final marked = RegExp(
    r'\b(only|first|unique|no ads|ad-free|offline|private|privacy|without|'
    r'instant|one tap|one-tap|unlimited|no account|no sign)\b',
    caseSensitive: false,
  );
  for (final clause in clauses) {
    if (!marked.hasMatch(clause)) continue;
    final lead = clause.split(RegExp(r'\s+[-–—]\s+|;')).first.trim();
    out.add(_sentenceCase(_shorten(lead, 7)));
    if (out.length == 2) break;
  }
  if (features.isNotEmpty) {
    final top = _sentenceCase(features.first.title.toLowerCase());
    if (!out.any((u) => u.toLowerCase() == top.toLowerCase())) out.add(top);
  }
  for (final usp in _uspFallbacks[category] ?? _genericUsps) {
    if (out.length >= 3) break;
    if (!out.contains(usp)) out.add(usp);
  }
  return out;
}

/// Differentiators any app of a kind can stand behind, for a description that
/// names none of its own.
const _uspFallbacks = <TemplateCategory, List<String>>{
  TemplateCategory.games: ['Easy to learn, hard to master', 'Short rounds'],
  TemplateCategory.music: ['Your library, beautifully organised'],
  TemplateCategory.finance: ['Every expense at a glance'],
  TemplateCategory.productivity: ['Everything in one place'],
};

const _genericUsps = ['Clean, focused design', 'Works the way you expect'];

// -----------------------------------------------------------------------------
// The plan
// -----------------------------------------------------------------------------

/// [length] screens: one per feature, most important first, then the
/// differentiators, then headlines any app of the kind can carry.
List<PlanItem> planFrom(
  List<ListingFeature> features,
  List<String> usps,
  TemplateCategory category, {
  int length = kDefaultPlanLength,
}) {
  final n = length.clamp(kMinPlanLength, kMaxPlanLength);
  final ranked = [...features]
    ..sort((a, b) => b.importance.compareTo(a.importance));
  final out = <PlanItem>[];
  final seen = <String>{};
  void add(String headline, String? subtitle) {
    final h = _shorten(headline, 6);
    if (h.isEmpty || !seen.add(h.toLowerCase()) || out.length >= n) return;
    final sub = subtitle?.trim();
    final fits = sub != null && _words(sub).length <= 10;
    out.add(PlanItem(h, subtitle: fits && _addsTo(h, sub) ? sub : null));
  }

  for (final f in ranked) {
    add(f.title, f.detail);
  }
  for (final u in usps) {
    add(_titleCase(u), null);
  }
  for (final (h, sub) in _closers[category] ?? _genericClosers) {
    add(h, sub);
  }
  var i = 1;
  while (out.length < n) {
    add('Highlight Feature ${out.length + i++}', null);
  }
  return out;
}

/// Whether [subtitle] says something [headline] does not — two content words
/// the headline lacks — rather than repeating it in a smaller size.
bool _addsTo(String headline, String? subtitle) {
  if (subtitle == null || subtitle.isEmpty) return false;
  final said = _words(headline).map(_stem).toSet();
  final fresh = _words(
    subtitle,
  ).where(_content).map(_stem).where((w) => !said.contains(w)).toSet();
  return fresh.length >= 2;
}

/// Headlines that close a listing of each kind.
const _closers = <TemplateCategory, List<(String, String?)>>{
  TemplateCategory.games: [
    ('Ready, Set, Play', 'Jump in and start your first run.'),
    ('Challenge Your Friends', 'See who gets the highest score.'),
    ('Play Anytime, Anywhere', null),
  ],
  TemplateCategory.music: [
    ('Your Soundtrack, Everywhere', null),
    ('Press Play', 'Your music is one tap away.'),
  ],
  TemplateCategory.finance: [
    ('Money, Made Clear', null),
    ('Plan Ahead With Confidence', null),
  ],
};

const List<(String, String?)> _genericClosers = [
  ('Everything in One Place', null),
  ('Start in Seconds', 'Download and get going today.'),
  ('Made for Every Day', null),
];

// -----------------------------------------------------------------------------
// Shaping text
// -----------------------------------------------------------------------------

/// A clause as a short title: the words before its first preposition, with
/// "all the arrow" mended to "all the arrows".
String _titleFrom(String clause) {
  var words = clause
      .replaceAll(RegExp(r'[^\w\s&+,\x27-]'), ' ')
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  // "You can …", "It lets you …", "This app helps you …"
  const lead = {
    'you',
    'can',
    'it',
    'lets',
    'let',
    'helps',
    'help',
    'this',
    'app',
    'the',
    'our',
    'we',
    'will',
    'allows',
    'to',
    'and',
    'a',
    'an',
  };
  while (words.length > 2 && lead.contains(words.first.toLowerCase())) {
    words = words.sublist(1);
  }
  const breaks = {
    'out',
    'of',
    'in',
    'on',
    'from',
    'with',
    'for',
    'by',
    'at',
    'into',
    'while',
    'when',
    'so',
    'that',
    'which',
    'because',
    'and',
    'or',
    'but',
    'to',
  };
  final kept = <String>[];
  for (final w in words) {
    if (kept.length >= 2 && breaks.contains(w.toLowerCase())) break;
    kept.add(w);
    if (kept.length == 5) break;
  }
  while (kept.length > 1 && _stopwords.contains(kept.last.toLowerCase())) {
    kept.removeLast();
  }
  if (kept.isNotEmpty) {
    kept[kept.length - 1] = kept.last.replaceAll(RegExp(r',+$'), '');
  }
  // "all the arrow" → "all the arrows"
  for (var i = 0; i < kept.length - 1; i++) {
    if (kept[i].toLowerCase() != 'all') continue;
    final j = i + 1 < kept.length && kept[i + 1].toLowerCase() == 'the'
        ? i + 2
        : i + 1;
    if (j < kept.length && !kept[j].toLowerCase().endsWith('s')) {
      kept[j] = '${kept[j]}s';
    }
  }
  return _titleCase(kept.join(' '));
}

/// [s] cut to [maxWords] words.
String _shorten(String s, int maxWords) {
  final words = s.trim().split(RegExp(r'\s+'));
  if (words.length <= maxWords) return s.trim();
  return words.take(maxWords).join(' ');
}

String _sentence(String clause) {
  final t = _sentenceCase(clause.trim());
  return RegExp(r'[.!?]$').hasMatch(t) ? t : '$t.';
}

String _sentenceCase(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

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
      else if (i > 0 && _minor.contains(w.toLowerCase()) && w != words.last)
        w.toLowerCase()
      // An acronym or a brand's own capitals stay as typed.
      else if (w.length > 1 && w.substring(1) != w.substring(1).toLowerCase())
        w
      else
        '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}',
  ].join(' ');
}
