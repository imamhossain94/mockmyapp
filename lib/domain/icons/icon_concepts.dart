/// Glyph concepts: starting points for an app icon, each a Lucide glyph on a
/// background in colours that read — free, offline, and editable in every
/// detail once picked.
///
/// Two engines, cheapest first. Built-in rules everywhere: the brief's
/// category and words choose glyphs, its colours (or its category's mood)
/// choose palettes, and the same brief always gives the same concepts. And the
/// device's own model where there is one, which picks from a shortlist the
/// rules drew up — its reply is JSON a small model may get wrong, so every
/// item is checked (a glyph from the list, colours that parse, a glyph that
/// stands out from its fill) and a reply with nothing usable in it is refused;
/// the rules then answer, and the page says so. Nothing leaves the device.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Alignment, HSLColor;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/assets/element_catalog.dart' show IconDef;
import '../../data/services/on_device_ai.dart';
import '../ai_backgrounds/design_palette.dart' show hexOf, paletteOf;
import '../engine/palette_roll.dart';
import '../models/icon_doc.dart';
import '../models/project.dart';
import '../models/screen_doc.dart';
import '../models/screen_template.dart';
import '../providers/on_device_ai_provider.dart';
import 'lucide_glyphs.dart';

/// What the concepts are drawn up for: the project's brief, as the icon page
/// reads it.
@immutable
class IconBrief {
  const IconBrief({
    required this.appName,
    this.description = '',
    this.category,
    this.keywords = const [],
    this.features = const [],
    this.palette = const [],
  });

  /// The project's brief — kept by the store copy page and the AI wizard —
  /// with the project's name standing in for an app name nobody wrote, and
  /// the colours its first screen is already made of.
  factory IconBrief.of(Project project) {
    final brief = project.brief;
    final name = brief.appName.trim().isNotEmpty
        ? brief.appName.trim()
        : (project.name.trim() == 'Untitled' ? '' : project.name.trim());
    final first = project.allScreens.firstOrNull;
    return IconBrief(
      appName: name,
      description: brief.description,
      category: brief.category,
      keywords: brief.keywords,
      features: [for (final f in brief.features) f.title],
      palette: first == null ? const [] : paletteOf(first, max: 3),
    );
  }

  final String appName;
  final String description;
  final TemplateCategory? category;
  final List<String> keywords;

  /// The features' titles — "Offline maps", "Every booking together".
  final List<String> features;

  /// Colours the listing already uses, which the first concept wears.
  final List<Color> palette;

  /// A seed that is the same for the same brief, moved on by [roll], so
  /// asking again gives new concepts and the same ask gives the same ones.
  int seedFor(int roll) {
    var hash = 0x811C9DC5;
    final text =
        '${appName.trim()}\u0000${category?.name ?? ''}\u0000'
        '${keywords.join(',')}\u0000${description.trim()}';
    for (final unit in utf8.encode(text)) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7FFFFFFF;
    }
    return (hash + roll * 7919) & 0x7FFFFFFF;
  }

  /// The words glyphs are matched on: keywords first, then the name, the
  /// features and the description, lower case, without the little words.
  List<String> get words {
    final seen = <String>{};
    final out = <String>[];
    void add(String text) {
      for (final raw in text.toLowerCase().split(RegExp(r'[^a-z0-9]+'))) {
        if (raw.length < 3 || _stopWords.contains(raw)) continue;
        if (seen.add(raw)) out.add(raw);
      }
    }

    keywords.forEach(add);
    add(appName);
    features.forEach(add);
    add(description);
    return out;
  }
}

const _stopWords = {
  'the',
  'and',
  'for',
  'with',
  'your',
  'you',
  'app',
  'apps',
  'all',
  'one',
  'that',
  'this',
  'from',
  'into',
  'out',
  'are',
  'can',
  'get',
  'has',
  'have',
  'its',
  'our',
  'new',
  'use',
  'any',
  'every',
  'more',
  'most',
  'make',
  'made',
  'just',
  'not',
  'but',
  'who',
  'what',
  'when',
  'where',
  'how',
  'way',
  'own',
  'free',
  'best',
  'top',
  'easy',
  'simple',
  'fast',
  'screen',
  'screens',
  'place',
  'time',
  'day',
  'days',
  'lets',
  'helps',
  'keep',
  'keeps',
};

/// One starting point: a name, why, and the icon itself.
@immutable
class IconConcept {
  const IconConcept({
    required this.name,
    required this.doc,
    this.rationale = '',
  });

  final String name;
  final String rationale;
  final IconDoc doc;
}

/// What a round of concepts came back with, and who drew it up.
@immutable
class IconConceptSet {
  const IconConceptSet(this.concepts, {required this.engine, this.note});

  final List<IconConcept> concepts;

  /// The device's model, or the built-in rules ([AiEngine.phrasebook]).
  final AiEngine engine;

  /// Why these are not what was asked for — the device's model answered with
  /// nothing usable, so the rules stepped in. Said beside the concepts.
  final String? note;
}

/// A model's reply that could not be used at all.
class IconConceptsRejected implements Exception {
  const IconConceptsRejected(this.reason);

  final String reason;

  @override
  String toString() => 'IconConceptsRejected: $reason';
}

/// How many concepts a round holds.
const kMinConcepts = 6;
const kMaxConcepts = 12;
const kDefaultConcepts = 8;

/// The least contrast a glyph may have against any colour of its fill. Three
/// to one is WCAG's floor for large marks; an icon's glyph is the largest
/// mark there is, and at 29 pt it needs every bit of it.
const kMinGlyphContrast = 3.0;

// -----------------------------------------------------------------------------
// Glyphs
// -----------------------------------------------------------------------------

/// Glyphs that read as an app's mark for each kind of app, best first. Every
/// name is held to the bundled set by a test.
const Map<TemplateCategory, List<String>> kCategoryGlyphs = {
  TemplateCategory.social: [
    'message-circle',
    'users',
    'heart',
    'messages-square',
    'thumbs-up',
    'at-sign',
    'hand-heart',
    'party-popper',
    'share-2',
    'user-round',
  ],
  TemplateCategory.productivity: [
    'square-check',
    'list-checks',
    'calendar-check',
    'clipboard-check',
    'notebook-pen',
    'timer',
    'target',
    'layers',
    'zap',
    'circle-check',
  ],
  TemplateCategory.finance: [
    'wallet',
    'piggy-bank',
    'coins',
    'banknote',
    'landmark',
    'trending-up',
    'chart-line',
    'receipt',
    'credit-card',
    'badge-dollar-sign',
  ],
  TemplateCategory.shopping: [
    'shopping-bag',
    'shopping-cart',
    'store',
    'tag',
    'gift',
    'package',
    'shirt',
    'gem',
    'ticket',
    'sparkles',
  ],
  TemplateCategory.food: [
    'utensils',
    'chef-hat',
    'coffee',
    'pizza',
    'cake-slice',
    'salad',
    'croissant',
    'soup',
    'cookie',
    'cup-soda',
  ],
  TemplateCategory.travel: [
    'compass',
    'plane',
    'map',
    'map-pin',
    'luggage',
    'globe',
    'mountain',
    'tent',
    'sailboat',
    'tree-palm',
  ],
  TemplateCategory.health: [
    'heart-pulse',
    'activity',
    'dumbbell',
    'footprints',
    'bike',
    'salad',
    'stethoscope',
    'brain',
    'flame',
    'droplet',
  ],
  TemplateCategory.education: [
    'graduation-cap',
    'book-open',
    'notebook-pen',
    'lightbulb',
    'brain',
    'pencil',
    'library',
    'school',
    'languages',
    'atom',
  ],
  TemplateCategory.entertainment: [
    'clapperboard',
    'film',
    'popcorn',
    'tv',
    'ticket',
    'star',
    'sparkles',
    'drama',
    'party-popper',
    'gamepad-2',
  ],
  TemplateCategory.music: [
    'music',
    'headphones',
    'disc-3',
    'mic',
    'radio',
    'guitar',
    'piano',
    'audio-waveform',
    'drum',
    'speaker',
  ],
  TemplateCategory.photoVideo: [
    'camera',
    'aperture',
    'image',
    'video',
    'film',
    'focus',
    'scan',
    'wand-sparkles',
    'clapperboard',
    'sparkles',
  ],
  TemplateCategory.games: [
    'gamepad-2',
    'swords',
    'trophy',
    'dice-5',
    'puzzle',
    'crown',
    'rocket',
    'target',
    'ghost',
    'joystick',
  ],
  TemplateCategory.lifestyle: [
    'sun',
    'leaf',
    'flower-2',
    'house',
    'sparkles',
    'coffee',
    'heart',
    'moon',
    'sofa',
    'palette',
  ],
  TemplateCategory.business: [
    'briefcase',
    'building',
    'presentation',
    'handshake',
    'users',
    'target',
    'landmark',
    'file-text',
    'trending-up',
    'chart-pie',
  ],
  TemplateCategory.utilities: [
    'wrench',
    'settings',
    'calculator',
    'scan-line',
    'battery-charging',
    'wifi',
    'shield-check',
    'folder',
    'cloud',
    'key-round',
  ],
};

/// What any app can wear, when the brief says little.
const kEverydayGlyphs = [
  'sparkles',
  'zap',
  'star',
  'rocket',
  'heart',
  'circle-check',
  'layers',
  'target',
  'sun',
  'shield-check',
  'gem',
  'leaf',
];

/// The Lucide categories each kind of app draws on beyond its own list.
const Map<TemplateCategory, List<String>> _lucideCategories = {
  TemplateCategory.social: ['social', 'communication', 'people', 'emoji'],
  TemplateCategory.productivity: ['time', 'files', 'text'],
  TemplateCategory.finance: ['finance', 'charts'],
  TemplateCategory.shopping: ['shopping'],
  TemplateCategory.food: ['food-beverage'],
  TemplateCategory.travel: ['travel', 'navigation', 'transportation'],
  TemplateCategory.health: ['medical', 'sports'],
  TemplateCategory.education: ['science', 'text'],
  TemplateCategory.entertainment: ['multimedia', 'gaming'],
  TemplateCategory.music: ['multimedia'],
  TemplateCategory.photoVideo: ['photography', 'multimedia'],
  TemplateCategory.games: ['gaming'],
  TemplateCategory.lifestyle: ['home', 'nature', 'weather', 'seasons'],
  TemplateCategory.business: ['buildings', 'charts', 'finance'],
  TemplateCategory.utilities: ['tools', 'devices', 'connectivity', 'security'],
};

/// Never suggested on their own: another company's mark, or a glyph that
/// reads as one at icon size. Still in the glyph picker, where the person
/// chooses for themselves.
const kAvoidedGlyphs = {
  'apple',
  'github',
  'gitlab',
  'figma',
  'framer',
  'chrome',
  'chromium',
  'twitter',
  'facebook',
  'instagram',
  'youtube',
  'slack',
  'codepen',
  'codesandbox',
  'dribbble',
  'linkedin',
  'trello',
  'twitch',
};

/// Lucide categories that make poor marks: text formatting, arrows, cursors,
/// layout scaffolding.
const _weakCategories = {'text', 'arrows', 'cursors', 'layout', 'math'};

/// The glyphs worth considering for [brief], best first: the category's own
/// list, then glyphs whose names or tags match the brief's words, then the
/// category's Lucide families, then everyday marks.
///
/// [icons] is the bundled set by name; names it does not hold are skipped,
/// so a renamed glyph cannot make a concept draw nothing.
List<String> candidateGlyphs(
  IconBrief brief,
  Map<String, IconDef> icons, {
  int max = 40,
}) {
  final scores = <String, double>{};
  void score(String name, double points) {
    if (!icons.containsKey(name) || kAvoidedGlyphs.contains(name)) return;
    scores[name] = (scores[name] ?? 0) + points;
  }

  final category = brief.category;
  final own = kCategoryGlyphs[category] ?? const <String>[];
  final families = _lucideCategories[category] ?? const <String>[];
  // The category's own marks lead: they were chosen to read as an app's
  // mark, which a glyph that merely shares a word with the brief may not.
  for (final (i, name) in own.indexed) {
    score(name, 10 - i * 0.3);
  }

  final words = brief.words;
  for (final (rank, word) in words.take(24).indexed) {
    // Earlier words — the keywords — count for more.
    final weight = 1 - rank / 48;
    for (final icon in icons.values) {
      if (icon.categories.every(_weakCategories.contains)) continue;
      // Once the kind of app is known, a glyph from outside its families
      // counts for half: "tickets" in a travel brief should find the ticket,
      // not a project board tagged "tickets".
      final inside =
          category == null ||
          own.contains(icon.name) ||
          icon.categories.any(families.contains);
      final reach = inside ? 1.0 : 0.5;
      final parts = icon.name.split('-');
      if (parts.contains(word) || (word.length >= 4 && parts.first == word)) {
        score(icon.name, 3 * weight * reach);
      } else if (icon.tags.any((t) => t == word || _stemMatch(t, word))) {
        score(icon.name, 1.2 * weight * reach);
      }
    }
  }

  for (final icon in icons.values) {
    if (icon.categories.any(families.contains) &&
        !icon.categories.every(_weakCategories.contains)) {
      score(icon.name, 0.4);
    }
  }

  for (final (i, name) in kEverydayGlyphs.indexed) {
    score(name, 1 - i * 0.05);
  }

  final ranked = scores.entries.toList()
    ..sort((a, b) {
      final byScore = b.value.compareTo(a.value);
      return byScore != 0 ? byScore : a.key.compareTo(b.key);
    });

  // One variant of a glyph family — `plane`, not `plane-landing` as well —
  // so a round of concepts is a choice of ideas, not of one idea's
  // spellings. The category's own list is exempt: `map` and `map-pin` are
  // both there on purpose.
  final seen = <String>{};
  final out = <String>[];
  for (final entry in ranked) {
    final family = entry.key.split('-').first;
    if (!own.contains(entry.key) && !seen.add(family)) continue;
    seen.add(family);
    out.add(entry.key);
    if (out.length >= max) break;
  }
  return out;
}

/// Whether [tag] and [word] are the same word give or take an ending —
/// "savings" and "saving", "workout" and "workouts".
bool _stemMatch(String tag, String word) {
  if (tag.length < 4 || word.length < 4) return false;
  String stem(String w) => w.replaceFirst(RegExp(r'(ing|ers|er|es|s)$'), '');
  final a = stem(tag);
  final b = stem(word);
  return a.length >= 4 && a == b;
}

/// A glyph's name as words: `map-pin` → "Map pin".
String glyphWords(String name) {
  final words = name.replaceAll(RegExp(r'-\d+$'), '').replaceAll('-', ' ');
  return words.isEmpty ? name : words[0].toUpperCase() + words.substring(1);
}

// -----------------------------------------------------------------------------
// Colour
// -----------------------------------------------------------------------------

double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// The worst contrast [glyph] has against any colour of [background].
double glyphContrast(Color glyph, Background background) {
  final colours = switch (background) {
    SolidBackground(:final color) => [color],
    final GradientBackground gradient => gradient.colors,
    // A pattern's motif colours sit under the glyph only faintly; its base
    // is what the glyph has to read against.
    PatternBackground(:final colors) => colors.take(1).toList(),
    ImageBackground() => const [Color(0xFFFFFFFF)],
  };
  if (colours.isEmpty) return 21;
  return colours.map((c) => contrastRatio(glyph, c)).reduce(math.min);
}

const _ink = Color(0xFF111827);
const _white = Color(0xFFFFFFFF);

/// White or near-black, whichever reads better on [background].
Color readableGlyph(Background background) =>
    glyphContrast(_white, background) >= glyphContrast(_ink, background)
    ? _white
    : _ink;

/// The patterns that make a calm ground for one glyph: soft fields of colour
/// rather than busy repeats that would fight it at 29 pt.
const kIconPatternStyles = [
  PatternStyle.mesh,
  PatternStyle.aurora,
  PatternStyle.blobs,
  PatternStyle.aura,
  PatternStyle.rays,
  PatternStyle.sunburst,
  PatternStyle.facets,
  PatternStyle.waves,
];

/// The colour harmony and ground each kind of app leans to.
PaletteHarmony _harmonyFor(TemplateCategory? category) => switch (category) {
  TemplateCategory.finance ||
  TemplateCategory.business ||
  TemplateCategory.utilities ||
  TemplateCategory.productivity => PaletteHarmony.monochrome,
  TemplateCategory.games ||
  TemplateCategory.entertainment ||
  TemplateCategory.shopping => PaletteHarmony.triadic,
  TemplateCategory.travel ||
  TemplateCategory.social ||
  TemplateCategory.lifestyle => PaletteHarmony.splitComplementary,
  TemplateCategory.music ||
  TemplateCategory.photoVideo ||
  TemplateCategory.health => PaletteHarmony.complementary,
  TemplateCategory.food ||
  TemplateCategory.education ||
  null => PaletteHarmony.analogous,
};

/// A strong, saturated pair to fill an icon with: icons want more colour
/// than a screenshot backdrop, so the roll's motif colours are the fill and
/// its pale base is left out.
(Color, Color) _fillPair(int seed, TemplateCategory? category) {
  final rolled = rollPalette(
    count: 3,
    seed: seed,
    harmony: _harmonyFor(category),
    dark: seed.isEven,
  );
  final a = rolled[1];
  final b = rolled[2];
  // Darken the deeper end a touch, so a gradient has depth to it.
  final hsl = HSLColor.fromColor(b);
  return (
    a,
    hsl.withLightness((hsl.lightness * 0.72).clamp(0.08, 0.9)).toColor(),
  );
}

// -----------------------------------------------------------------------------
// The rules
// -----------------------------------------------------------------------------

/// The built-in rules' concepts for [brief]: glyphs from [candidateGlyphs],
/// each on a background that varies round by round — a diagonal gradient, a
/// solid, a radial glow, a calm pattern — with the glyph in whichever of white
/// and near-black reads best. The first wears the listing's own colours when
/// it has two.
///
/// Free, offline and deterministic: the same brief and [roll] always give the
/// same concepts, and the next [roll] new ones. [count] is held to
/// [kMinConcepts]–[kMaxConcepts].
List<IconConcept> ruleIconConcepts(
  IconBrief brief,
  Map<String, IconDef> icons, {
  int count = kDefaultConcepts,
  int roll = 0,
}) {
  final want = count.clamp(kMinConcepts, kMaxConcepts);
  var glyphs = candidateGlyphs(brief, icons);
  if (glyphs.isEmpty) {
    glyphs = [
      for (final name in kEverydayGlyphs)
        if (icons.containsKey(name)) name,
    ];
  }
  if (glyphs.isEmpty) return const [];
  final seedBase = brief.seedFor(roll);
  final random = math.Random(seedBase);
  final matched = brief.category != null || brief.words.isNotEmpty;
  final out = <IconConcept>[];
  for (var i = 0; i < want; i++) {
    final glyph = glyphs[(roll * want + i) % glyphs.length];
    final seed = (seedBase + i * 104729) & 0x7FFFFFFF;
    final own = i == 0 && brief.palette.length >= 2;
    final (a, b) = own
        ? (brief.palette[0], brief.palette[1])
        : _fillPair(seed, brief.category);
    final Background background = switch ((i + roll) % 4) {
      0 => GradientBackground(
        colorOne: a,
        colorTwo: b,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      1 => SolidBackground(a),
      2 => GradientBackground(colorOne: a, colorTwo: b, radial: true),
      _ => PatternBackground(
        style: kIconPatternStyles[random.nextInt(kIconPatternStyles.length)],
        colors: [b, a, Color.lerp(a, _white, 0.35)!],
        seed: seed,
        scale: 1 + random.nextDouble() * 0.6,
        angle: (random.nextDouble() * 360).roundToDouble(),
        intensity: 0.55 + random.nextDouble() * 0.25,
      ),
    };
    // The first ground on which one of the two inks reads: the design
    // itself, or a plain fill of either of its colours — so the person's own
    // colours are never darkened while one of them carries a glyph as it is.
    // Only when none does is the design deepened until white reads.
    final grounds = [background, SolidBackground(a), SolidBackground(b)];
    final ground = grounds.firstWhere(
      (g) => glyphContrast(readableGlyph(g), g) >= kMinGlyphContrast,
      orElse: () => _deepened(background),
    );
    out.add(
      IconConcept(
        name: glyphWords(glyph),
        rationale: own
            ? "In your listing's colours."
            : matched
            ? 'Picked for your brief.'
            : 'A versatile mark to start from.',
        doc: IconDoc(
          background: ground,
          foreground: IconGlyph(glyph),
          glyphColor: readableGlyph(ground),
          // A touch heavier than Lucide's line: it holds up at settings-list
          // sizes, where the thinnest strokes go first.
          stroke: 1.3,
        ),
      ),
    );
  }
  return out;
}

/// [background] darkened until white reads on it.
Background _deepened(Background background) {
  Color deep(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness(math.min(hsl.lightness, 0.32)).toColor();
  }

  return switch (background) {
    SolidBackground(:final color) => SolidBackground(deep(color)),
    final GradientBackground g => g.copyWith(
      colorOne: deep(g.colorOne),
      colorTwo: deep(g.colorTwo),
    ),
    final PatternBackground p => p.copyWith(
      colors: [for (final c in p.colors) deep(c)],
    ),
    ImageBackground() => background,
  };
}

// -----------------------------------------------------------------------------
// On the device
// -----------------------------------------------------------------------------

/// What the device's model is told: the house rules for icon concepts.
const kIconConceptInstructions =
    'You design app icons. Reply with only a JSON array and no other text. '
    'Each item is an object: {"name": "two or three words", "glyph": "one of '
    'the listed glyphs", "colors": ["#RRGGBB", "#RRGGBB"], "glyphColor": '
    '"#RRGGBB"}. The first colour fills the icon and a second, if given, makes '
    'it a gradient. The glyph colour must stand out strongly against the '
    'fill. Use only glyph names from the list, each once. No brand names, no '
    'text, no emoji.';

/// The request for [count] concepts for [brief], choosing from [candidates].
String iconConceptPrompt(
  IconBrief brief,
  List<String> candidates, {
  int count = kDefaultConcepts,
}) {
  String cut(String text, int max) {
    final t = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    return t.length <= max ? t : t.substring(0, max).trimRight();
  }

  return [
    'Glyphs: ${candidates.join(', ')}',
    if (brief.appName.trim().isNotEmpty) 'App: ${cut(brief.appName, 60)}',
    if (brief.category case final category?) 'Category: ${category.label}',
    if (brief.description.trim().isNotEmpty)
      'About: ${cut(brief.description, 300)}',
    if (brief.keywords.isNotEmpty)
      'Keywords: ${cut(brief.keywords.take(10).join(', '), 200)}',
    if (brief.palette.isNotEmpty)
      'Brand colours: ${brief.palette.map(hexOf).join(', ')}',
    'Suggest $count different icons.',
  ].join('\n');
}

/// `#RRGGBB` (the `#` optional) as an opaque colour, or null.
Color? _hex(Object? value) {
  if (value is! String) return null;
  final m = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(value.trim());
  if (m == null) return null;
  return Color(0xFF000000 | int.parse(m[1]!, radix: 16));
}

/// The JSON inside [reply], or throws [IconConceptsRejected]: tolerant of a
/// code fence, a sentence before the array, or the array under a key.
Object? _decodeJson(String reply) {
  var text = reply.trim();
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(text);
  if (fence != null) text = fence[1]!.trim();
  final start = text.indexOf(RegExp(r'[\[{]'));
  if (start < 0) throw const IconConceptsRejected('no JSON in the reply');
  final close = text[start] == '[' ? ']' : '}';
  final end = text.lastIndexOf(close);
  if (end <= start) throw const IconConceptsRejected('the JSON is cut short');
  try {
    return jsonDecode(text.substring(start, end + 1));
  } on FormatException {
    throw const IconConceptsRejected('the JSON does not parse');
  }
}

/// Reads a device model's reply into concepts, or throws
/// [IconConceptsRejected].
///
/// Strict about what is inside: an item whose glyph is not one of
/// [candidates], whose colours do not parse, or whose glyph would not stand
/// out from its fill ([kMinGlyphContrast]) is dropped — never repaired into
/// something the model did not say. A glyph colour left out is chosen; one
/// given badly drops the item. No item left, and the reply is refused.
List<IconConcept> parseDeviceIconReply(
  String reply, {
  required List<String> candidates,
  int max = kMaxConcepts,
}) {
  final decoded = _decodeJson(reply);
  final items = switch (decoded) {
    final List<Object?> list => list,
    final Map<Object?, Object?> map when map['icons'] is List =>
      map['icons']! as List<Object?>,
    final Map<Object?, Object?> map when map['concepts'] is List =>
      map['concepts']! as List<Object?>,
    _ => throw const IconConceptsRejected('not a JSON list'),
  };
  final allowed = {for (final c in candidates) c.toLowerCase(): c};
  final used = <String>{};
  final out = <IconConcept>[];
  for (final item in items) {
    if (out.length >= max) break;
    if (item is! Map) continue;
    final glyph = allowed[('${item['glyph'] ?? ''}').trim().toLowerCase()];
    if (glyph == null || !used.add(glyph)) continue;
    final rawColours = item['colors'] ?? item['colours'];
    final colours = rawColours is List
        ? [for (final c in rawColours) ?_hex(c)]
        : [?_hex(rawColours)];
    if (colours.isEmpty) continue;
    final Background background = colours.length == 1
        ? SolidBackground(colours.first)
        : GradientBackground(
            colorOne: colours[0],
            colorTwo: colours[1],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );
    final Color ink;
    if (item['glyphColor'] == null) {
      ink = readableGlyph(background);
    } else {
      final given = _hex(item['glyphColor']);
      if (given == null) continue;
      ink = given;
    }
    if (glyphContrast(ink, background) < kMinGlyphContrast) continue;
    final rawName = item['name'];
    final name = rawName is String ? rawName.trim() : '';
    out.add(
      IconConcept(
        name: name.isEmpty
            ? glyphWords(glyph)
            : (name.length <= 40 ? name : name.substring(0, 40).trimRight()),
        rationale: 'Suggested by the AI on this device.',
        doc: IconDoc(
          background: background,
          foreground: IconGlyph(glyph),
          glyphColor: ink,
          stroke: 1.3,
        ),
      ),
    );
  }
  if (out.isEmpty) {
    throw const IconConceptsRejected('no concept in it holds together');
  }
  return out;
}

// -----------------------------------------------------------------------------
// The director
// -----------------------------------------------------------------------------

/// Concepts on the device: its model where there is one, the rules where
/// there is not — or where the model answered with nothing usable.
class IconConceptDirector {
  const IconConceptDirector(this.model);

  /// The device's model, or null where there is none.
  final TextCompleter? model;

  /// What [suggest] would use right now: the model, or the rules.
  Future<AiEngine> engine() async {
    final m = model;
    if (m != null) {
      try {
        final status = await m.completerStatus();
        if (status.usable) return status.engine;
      } catch (error) {
        debugPrint('No device model for icon concepts: $error');
      }
    }
    return AiEngine.phrasebook;
  }

  Future<IconConceptSet> suggest(
    IconBrief brief,
    Map<String, IconDef> icons, {
    int count = kDefaultConcepts,
    int roll = 0,
  }) async {
    IconConceptSet rules({String? note}) => IconConceptSet(
      ruleIconConcepts(brief, icons, count: count, roll: roll),
      engine: AiEngine.phrasebook,
      note: note,
    );
    final m = model;
    if (m == null) return rules();
    try {
      final status = await m.completerStatus();
      if (!status.usable) return rules();
      // The shortlist moves on with the roll, so asking again offers the
      // model new glyphs as well as a new chance.
      final shortlist = candidateGlyphs(brief, icons, max: 60);
      final offset = shortlist.isEmpty ? 0 : (roll * 12) % shortlist.length;
      final candidates = [
        ...shortlist.skip(offset),
        ...shortlist.take(offset),
      ].take(40).toList();
      final reply = await m.complete(
        instructions: kIconConceptInstructions,
        prompt: iconConceptPrompt(brief, candidates, count: count),
      );
      final picked = parseDeviceIconReply(
        reply,
        candidates: candidates,
        max: count.clamp(kMinConcepts, kMaxConcepts),
      );
      if (picked.length >= kMinConcepts) {
        return IconConceptSet(picked, engine: status.engine);
      }
      // Fewer than a round: the rules make up the rest, and say so.
      final taken = {for (final c in picked) c.doc.glyph};
      final more = [
        for (final c in ruleIconConcepts(
          brief,
          icons,
          count: kMaxConcepts,
          roll: roll,
        ))
          if (!taken.contains(c.doc.glyph)) c,
      ];
      return IconConceptSet(
        [...picked, ...more.take(kMinConcepts - picked.length)],
        engine: status.engine,
        note:
            'The AI on this device suggested ${picked.length}; the rest come '
            'from the built-in suggestions.',
      );
    } on IconConceptsRejected catch (error) {
      debugPrint('Device icon concepts refused: $error');
      return rules(
        note:
            "The AI on this device didn't give a usable answer, so these "
            'come from the built-in suggestions.',
      );
    } on OnDeviceAiException catch (error) {
      debugPrint('Device icon concepts failed: $error');
      return rules(
        note:
            "The AI on this device couldn't answer, so these come from the "
            'built-in suggestions.',
      );
    }
  }
}

final iconConceptDirectorProvider = Provider<IconConceptDirector>(
  (ref) => IconConceptDirector(ref.watch(textCompleterProvider)),
);

/// The built-in rules' first concept for [project]'s brief: where a project
/// the AI wizard makes starts its icon, free and offline. Null only when no
/// glyph could be loaded.
Future<IconDoc?> firstConceptFor(Project project) async {
  final icons = await LucideGlyphs.load();
  return ruleIconConcepts(IconBrief.of(project), icons).firstOrNull?.doc;
}
