/// AI art direction: a model reads a short brief and picks pattern
/// backgrounds for it — style, palette, scale, angle, intensity — which the
/// app then paints itself.
///
/// The cheapest AI background there is, and the most useful one: what comes
/// back is an ordinary [PatternBackground], so it is editable in the Pattern
/// tool, resolution-free, byte-identical on every re-export, and a panorama
/// across any number of screens for nothing (`docs/05-GENERATED-BACKGROUNDS.md`).
///
/// Two engines, both on the device: its own model where there is one
/// (nothing leaves the device), and built-in rules everywhere (deterministic).
/// A device model's reply is JSON a small model may get wrong, so it is
/// checked field by field and refused when it does not hold together; the
/// rules then answer, and the person is told.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/on_device_ai.dart';
import '../engine/palette_roll.dart';
import '../models/screen_doc.dart';
import '../providers/on_device_ai_provider.dart';
import 'design_palette.dart';

/// What art direction is asked to dress.
@immutable
class ArtBrief {
  const ArtBrief({
    required this.appName,
    this.mood = '',
    this.palette = const [],
    this.screens = 1,
  });

  /// The project's name.
  final String appName;

  /// The person's own words — "calm travel planner, sunrise colours".
  final String mood;

  /// The colours the design already uses ([paletteOf]); may be empty.
  final List<Color> palette;

  /// How many screens one background should run across. Above one asks for
  /// styles that read as one picture across a set, and gives every suggestion
  /// that many slices — a panorama.
  final int screens;

  /// A seed that is the same for the same brief, moved on by [roll] — so
  /// asking again gives new compositions, and the same ask gives the same.
  int seedFor(int roll) {
    var hash = 0x811C9DC5;
    for (final unit in utf8.encode('${appName.trim()}\u0000${mood.trim()}')) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7FFFFFFF;
    }
    return (hash + roll * 7919) & 0x7FFFFFFF;
  }
}

/// One suggested background: a name, why, and the pattern itself.
@immutable
class ArtSuggestion {
  const ArtSuggestion({
    required this.name,
    required this.background,
    this.rationale = '',
  });

  final String name;
  final String rationale;
  final PatternBackground background;
}

/// What art direction came back with, and who made it.
@immutable
class ArtDirection {
  const ArtDirection(this.suggestions, {required this.engine, this.note});

  final List<ArtSuggestion> suggestions;

  /// The device's model, or the built-in rules ([AiEngine.phrasebook]).
  final AiEngine engine;

  /// Why these are not what was asked for — the device's model answered with
  /// nothing usable, so the rules stepped in. Said beside the result.
  final String? note;
}

/// A model's reply that could not be used at all: not JSON, or no suggestion
/// in it that holds together.
class ArtDirectionRejected implements Exception {
  const ArtDirectionRejected(this.reason);

  final String reason;

  @override
  String toString() => 'ArtDirectionRejected: $reason';
}

// -----------------------------------------------------------------------------
// The pattern's ranges
// -----------------------------------------------------------------------------

/// The Background panel's slider ranges, which every suggestion is clamped
/// to, so what a model suggests is always something the panel can edit.
abstract final class ArtRanges {
  static const scaleMin = 0.4;
  static const scaleMax = 2.5;
  static const angleMax = 360.0;
  static const intensityMin = 0.1;
  static const intensityMax = 1.0;
  static const colorsMin = 2;
  static const colorsMax = 4;
  static const symbolCountMin = 4;
  static const symbolCountMax = 200;
  static const symbolOpacityMin = 0.05;
  static const symbolCenterMax = 0.5;
}

/// The styles a device model may choose from: every one but the symbol
/// field, whose choice of glyphs is more than a small model gets right.
final List<PatternStyle> kArtStyles = [
  for (final style in PatternStyle.values)
    if (style != PatternStyle.symbols) style,
];

/// Styles that read as one picture running across several screens rather
/// than a tile repeated — what a panorama is asked for.
const _panoramaStyles = {
  PatternStyle.mesh,
  PatternStyle.blobs,
  PatternStyle.aurora,
  PatternStyle.waves,
  PatternStyle.terrain,
  PatternStyle.dunes,
  PatternStyle.ridges,
  PatternStyle.strata,
  PatternStyle.crestTop,
  PatternStyle.crestBottom,
  PatternStyle.crestFull,
  PatternStyle.isobars,
  PatternStyle.topography,
  PatternStyle.starfield,
  PatternStyle.bokeh,
  PatternStyle.beams,
};

/// A style's name in words: `crestTop` → "Crest top".
String styleWords(PatternStyle style) {
  final words = style.name.replaceAllMapped(
    RegExp('[A-Z]'),
    (m) => ' ${m[0]!.toLowerCase()}',
  );
  return words[0].toUpperCase() + words.substring(1);
}

/// Thrown inside the parser for a field of the wrong type.
class _Bad implements Exception {
  const _Bad();
}

/// A number the model may leave out (null) but may not get wrong.
double? _number(Object? value) {
  if (value == null) return null;
  if (value is! num || !value.isFinite) throw const _Bad();
  return value.toDouble();
}

/// `#RRGGBB` (the `#` optional) as an opaque colour, or null.
Color? _hex(Object? value) {
  if (value is! String) return null;
  final m = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(value.trim());
  if (m == null) return null;
  return Color(0xFF000000 | int.parse(m[1]!, radix: 16));
}

/// One of [kArtStyles] by name, or null: the symbol field is never a model's
/// to choose.
PatternStyle? _style(Object? name) {
  if (name is! String) return null;
  final wanted = name.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
  for (final style in kArtStyles) {
    if (style.name.toLowerCase() == wanted) return style;
  }
  return null;
}

String _text(Object? value, int max) {
  if (value is! String) return '';
  final t = value.trim();
  return t.length <= max ? t : t.substring(0, max).trimRight();
}

// -----------------------------------------------------------------------------
// On the device
// -----------------------------------------------------------------------------

/// What the device's model is told: the house rules for art direction.
const kArtDirectionInstructions =
    'You are an art director choosing backgrounds for app store screenshots. '
    'Reply with only a JSON array and no other text. Each item is an object: '
    '{"name": "two or three words", "style": "one of the listed styles", '
    '"colors": ["#RRGGBB", "#RRGGBB", "#RRGGBB"], "scale": 0.4 to 2.5, '
    '"angle": 0 to 360, "intensity": 0.1 to 1}. '
    'The first colour is the base fill and the others paint the pattern over '
    'it; keep two to four colours, with enough contrast for a white or a dark '
    'headline. Use the brand colours when they are given. No brand names, no '
    'text, no emoji.';

/// The request for [count] suggestions for [brief].
String artDirectionPrompt(ArtBrief brief, {int count = 4}) {
  final styles = brief.screens > 1
      ? kArtStyles.where(_panoramaStyles.contains)
      : kArtStyles;
  final lines = [
    'Styles: ${styles.map((s) => s.name).join(', ')}',
    if (brief.appName.trim().isNotEmpty)
      'App: ${_text(brief.appName, kMaxAppNameChars)}',
    if (brief.mood.trim().isNotEmpty)
      'Mood: ${_text(brief.mood, kMaxMoodChars)}',
    if (brief.palette.isNotEmpty)
      'Brand colours: ${brief.palette.map(hexOf).join(', ')}',
    if (brief.screens > 1)
      'Each background runs across ${brief.screens} screens side by side, so '
          'choose styles that flow as one wide picture.',
    'Suggest $count different backgrounds.',
  ];
  return lines.join('\n');
}

/// Reads a device model's reply into suggestions, or throws
/// [ArtDirectionRejected].
///
/// Tolerant of the wrapping small models add — a code fence, a sentence
/// before the array, an object holding it under `suggestions` — and strict
/// about what is inside: an item whose style is not one of [kArtStyles], with
/// fewer than two `#RRGGBB` colours, or with a number of the wrong type, is
/// dropped; numbers out of range are brought into it. No item left, and the
/// whole reply is refused.
///
/// The seed is the app's ([seedBase] onwards), never the model's: the same
/// suggestion must always paint the same picture.
List<ArtSuggestion> parseDeviceArtReply(
  String reply, {
  required ArtBrief brief,
  required int seedBase,
  int max = 6,
}) {
  final decoded = _decodeJson(reply);
  final items = switch (decoded) {
    final List<Object?> list => list,
    final Map<Object?, Object?> map when map['suggestions'] is List =>
      map['suggestions']! as List<Object?>,
    _ => throw const ArtDirectionRejected('not a JSON list'),
  };
  final out = <ArtSuggestion>[];
  for (final item in items) {
    if (out.length >= max) break;
    if (item is! Map) continue;
    final suggestion = _deviceSuggestion(
      item.cast<Object?, Object?>(),
      seed: (seedBase + out.length * 104729) & 0x7FFFFFFF,
      slices: brief.screens,
    );
    if (suggestion != null) out.add(suggestion);
  }
  if (out.isEmpty) {
    throw const ArtDirectionRejected('no suggestion in it holds together');
  }
  return out;
}

/// The JSON inside [reply], or throws [ArtDirectionRejected].
Object? _decodeJson(String reply) {
  var text = reply.trim();
  // A fenced block: keep what is inside it.
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(text);
  if (fence != null) text = fence[1]!.trim();
  final start = text.indexOf(RegExp(r'[\[{]'));
  if (start < 0) throw const ArtDirectionRejected('no JSON in the reply');
  final close = text[start] == '[' ? ']' : '}';
  final end = text.lastIndexOf(close);
  if (end <= start) throw const ArtDirectionRejected('the JSON is cut short');
  try {
    return jsonDecode(text.substring(start, end + 1));
  } on FormatException {
    throw const ArtDirectionRejected('the JSON does not parse');
  }
}

ArtSuggestion? _deviceSuggestion(
  Map<Object?, Object?> item, {
  required int seed,
  required int slices,
}) {
  final style = _style(item['style']);
  if (style == null) return null;
  final rawColors = item['colors'];
  if (rawColors is! List) return null;
  final colors = [
    for (final c in rawColors) ?_hex(c),
  ].take(ArtRanges.colorsMax).toList();
  if (colors.length < ArtRanges.colorsMin) return null;
  final double? scale, angle, intensity;
  try {
    scale = _number(item['scale']);
    angle = _number(item['angle']);
    intensity = _number(item['intensity']);
  } on _Bad {
    return null;
  }
  final name = _text(item['name'], 40);
  return ArtSuggestion(
    name: name.isEmpty ? styleWords(style) : name,
    rationale: _text(item['rationale'] ?? item['why'], 160),
    background: PatternBackground(
      style: style,
      colors: colors,
      seed: seed,
      scale: (scale ?? 1).clamp(ArtRanges.scaleMin, ArtRanges.scaleMax),
      angle: (angle ?? 0).clamp(0, ArtRanges.angleMax),
      intensity: (intensity ?? 0.8).clamp(
        ArtRanges.intensityMin,
        ArtRanges.intensityMax,
      ),
      slices: math.max(1, slices),
    ),
  );
}

// -----------------------------------------------------------------------------
// The rules
// -----------------------------------------------------------------------------

/// Words in a brief, the styles they suggest, and how to colour them.
typedef _Mood = ({
  List<String> words,
  List<PatternStyle> styles,
  PaletteHarmony? harmony,
  bool? dark,
});

const List<_Mood> _moods = [
  (
    words: ['calm', 'relax', 'sleep', 'meditat', 'zen', 'mindful', 'yoga'],
    styles: [
      PatternStyle.aurora,
      PatternStyle.mesh,
      PatternStyle.dunes,
      PatternStyle.waves,
      PatternStyle.aura,
    ],
    harmony: PaletteHarmony.analogous,
    dark: null,
  ),
  (
    words: ['night', 'dark', 'space', 'star', 'astro', 'galaxy', 'moon'],
    styles: [
      PatternStyle.starfield,
      PatternStyle.stage,
      PatternStyle.aurora,
      PatternStyle.bokeh,
    ],
    harmony: null,
    dark: true,
  ),
  (
    words: ['game', 'play', 'fun', 'kid', 'arcade', 'puzzle', 'party'],
    styles: [
      PatternStyle.confetti,
      PatternStyle.poster,
      PatternStyle.bubbles,
      PatternStyle.zigzag,
      PatternStyle.beams,
    ],
    harmony: PaletteHarmony.triadic,
    dark: false,
  ),
  (
    words: ['financ', 'bank', 'money', 'budget', 'invest', 'business', 'work'],
    styles: [
      PatternStyle.grid,
      PatternStyle.isometric,
      PatternStyle.facets,
      PatternStyle.stage,
      PatternStyle.strata,
    ],
    harmony: PaletteHarmony.monochrome,
    dark: null,
  ),
  (
    words: ['travel', 'trip', 'sun', 'beach', 'holiday', 'outdoor', 'hike'],
    styles: [
      PatternStyle.terrain,
      PatternStyle.dunes,
      PatternStyle.sunburst,
      PatternStyle.crestBottom,
      PatternStyle.ridges,
    ],
    harmony: PaletteHarmony.splitComplementary,
    dark: false,
  ),
  (
    words: ['music', 'audio', 'sound', 'podcast', 'song', 'radio', 'beat'],
    styles: [
      PatternStyle.waves,
      PatternStyle.rings,
      PatternStyle.strata,
      PatternStyle.isobars,
    ],
    harmony: PaletteHarmony.complementary,
    dark: true,
  ),
  (
    words: ['tech', 'code', 'developer', 'data', 'network', 'smart', ' ai'],
    styles: [
      PatternStyle.circuit,
      PatternStyle.grid,
      PatternStyle.isobars,
      PatternStyle.beams,
      PatternStyle.facets,
    ],
    harmony: PaletteHarmony.complementary,
    dark: true,
  ),
  (
    words: ['health', 'fitness', 'sport', 'run', 'gym', 'workout', 'energy'],
    styles: [
      PatternStyle.beams,
      PatternStyle.rays,
      PatternStyle.crestFull,
      PatternStyle.aura,
      PatternStyle.sunburst,
    ],
    harmony: PaletteHarmony.complementary,
    dark: null,
  ),
  (
    words: ['photo', 'camera', 'video', 'film', 'design', 'art', 'creative'],
    styles: [
      PatternStyle.bokeh,
      PatternStyle.spotlight,
      PatternStyle.prism,
      PatternStyle.mesh,
    ],
    harmony: null,
    dark: true,
  ),
  (
    words: ['food', 'recipe', 'cook', 'kitchen', 'restaurant', 'coffee'],
    styles: [
      PatternStyle.blobs,
      PatternStyle.crestTop,
      PatternStyle.dots,
      PatternStyle.dunes,
    ],
    harmony: PaletteHarmony.analogous,
    dark: false,
  ),
  (
    words: ['learn', 'study', 'school', 'educat', 'read', 'book', 'language'],
    styles: [
      PatternStyle.topography,
      PatternStyle.grid,
      PatternStyle.crestTop,
      PatternStyle.halftone,
    ],
    harmony: PaletteHarmony.analogous,
    dark: false,
  ),
  (
    words: ['social', 'chat', 'friend', 'message', 'community', 'love'],
    styles: [
      PatternStyle.blobs,
      PatternStyle.bubbles,
      PatternStyle.mesh,
      PatternStyle.aura,
    ],
    harmony: PaletteHarmony.splitComplementary,
    dark: null,
  ),
];

const _everyday = [
  PatternStyle.mesh,
  PatternStyle.blobs,
  PatternStyle.aurora,
  PatternStyle.facets,
  PatternStyle.waves,
  PatternStyle.poster,
];

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// A palette for one suggestion in the mood's harmony, rolled until its motif
/// reads against its base — as [rollReadablePalette] does, with the mood's
/// harmony and ground kept.
List<Color> _palette(int seed, PaletteHarmony? harmony, bool? dark) {
  List<Color>? best;
  var bestRatio = 0.0;
  for (var i = 0; i < 12; i++) {
    final colors = rollPalette(
      count: 3,
      seed: seed + i * 7919,
      harmony: harmony,
      dark: dark,
    );
    final ratio = _contrast(colors.first, colors[1]);
    if (ratio >= 1.9) return colors;
    if (ratio > bestRatio) {
      bestRatio = ratio;
      best = colors;
    }
  }
  return best!;
}

/// The built-in rules' art direction: styles from the words in the brief,
/// palettes in the mood's harmony, the design's own colours first.
///
/// Free, offline and deterministic — the same brief and [roll] always give
/// the same suggestions, and the next [roll] gives new ones.
List<ArtSuggestion> ruleArtDirection(
  ArtBrief brief, {
  int count = 4,
  int roll = 0,
}) {
  final text = ' ${brief.appName} ${brief.mood} '.toLowerCase();
  final matched = [
    for (final mood in _moods)
      if (mood.words.any(text.contains)) mood,
  ];
  final harmony = matched.firstOrNull?.harmony;
  final dark = matched.firstOrNull?.dark;
  var styles = <PatternStyle>[
    for (final mood in matched) ...mood.styles,
    ..._everyday,
  ];
  if (brief.screens > 1) {
    final wide = styles.where(_panoramaStyles.contains).toList();
    styles = wide.isEmpty ? _panoramaStyles.toList() : wide;
  }
  styles = styles.toSet().toList();

  final seedBase = brief.seedFor(roll);
  final random = math.Random(seedBase);
  final offset = roll * count;
  final out = <ArtSuggestion>[];
  for (var i = 0; i < count; i++) {
    final style = styles[(offset + i) % styles.length];
    final seed = (seedBase + i * 104729) & 0x7FFFFFFF;
    final ownColours = i == 0 && brief.palette.length >= 2;
    final colors = ownColours
        ? brief.palette.take(ArtRanges.colorsMax).toList()
        : _palette(seed, harmony, dark);
    out.add(
      ArtSuggestion(
        name: ownColours
            ? '${styleWords(style)} in your colours'
            : styleWords(style),
        rationale: matched.isEmpty
            ? 'A versatile backdrop that leaves room for the screenshot.'
            : 'Picked for the words in your brief.',
        background: PatternBackground(
          style: style,
          colors: colors,
          seed: seed,
          scale: 0.8 + random.nextDouble() * 0.8,
          angle: (random.nextDouble() * 360).roundToDouble(),
          intensity: 0.65 + random.nextDouble() * 0.3,
          slices: math.max(1, brief.screens),
        ),
      ),
    );
  }
  return out;
}

// -----------------------------------------------------------------------------
// The directors
// -----------------------------------------------------------------------------

/// Art direction on the device: its model where there is one, the rules
/// where there is not — or where the model answered with nothing usable.
class ArtDirector {
  const ArtDirector(this.model);

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
        debugPrint('No device model for art direction: $error');
      }
    }
    return AiEngine.phrasebook;
  }

  Future<ArtDirection> suggest(
    ArtBrief brief, {
    int count = 4,
    int roll = 0,
  }) async {
    ArtDirection rules({String? note}) => ArtDirection(
      ruleArtDirection(brief, count: count, roll: roll),
      engine: AiEngine.phrasebook,
      note: note,
    );
    final m = model;
    if (m == null) return rules();
    try {
      final status = await m.completerStatus();
      if (!status.usable) return rules();
      final reply = await m.complete(
        instructions: kArtDirectionInstructions,
        prompt: artDirectionPrompt(brief, count: count),
      );
      return ArtDirection(
        parseDeviceArtReply(
          reply,
          brief: brief,
          seedBase: brief.seedFor(roll),
          max: count,
        ),
        engine: status.engine,
      );
    } on ArtDirectionRejected catch (error) {
      debugPrint('Device art direction refused: $error');
      return rules(
        note:
            "The AI on this device didn't give a usable answer, so these "
            'come from the built-in suggestions.',
      );
    } on OnDeviceAiException catch (error) {
      debugPrint('Device art direction failed: $error');
      return rules(
        note:
            "The AI on this device couldn't answer, so these come from the "
            'built-in suggestions.',
      );
    }
  }
}

final artDirectorProvider = Provider<ArtDirector>(
  (ref) => ArtDirector(ref.watch(textCompleterProvider)),
);
