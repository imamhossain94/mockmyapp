/// What the AI screenshot generator knows about an app before it designs a
/// listing for it: the category, the audience, the features worth a
/// screenshot each, the words people search for, and one headline per screen.
///
/// Plain immutable values, so the wizard can edit any part of an analysis and
/// the ASO score can be worked out again from whatever the user ended up with.
/// Nothing here knows whether a model or the built-in rules produced it — that
/// is recorded in [ListingAnalysis.engine] and shown, never acted on.
library;

import 'package:flutter/foundation.dart';

import '../../data/services/on_device_ai.dart';
import '../models/screen_template.dart';

/// The fewest and most features an analysis carries. Fewer than three cannot
/// fill a listing; more than six is a list nobody reads on a phone.
const kMinFeatures = 3;
const kMaxFeatures = 6;

/// How long a product description may be, in characters.
const kMinDescription = 50;
const kMaxDescription = 10000;

/// How many screens a plan has unless the user says otherwise, and the range
/// they may choose from. Both stores take up to eight phone screenshots, and
/// fewer than three is not a listing.
const kDefaultPlanLength = 5;
const kMinPlanLength = 3;
const kMaxPlanLength = 8;

/// One thing the app does, as a screenshot would sell it.
@immutable
class ListingFeature {
  const ListingFeature({
    required this.title,
    this.detail = '',
    this.importance = 7,
  });

  /// Two to five words, title case.
  final String title;

  /// One sentence on what the user gets.
  final String detail;

  /// How much this feature matters to the listing, 1–10.
  final int importance;

  ListingFeature copyWith({String? title, String? detail, int? importance}) =>
      ListingFeature(
        title: title ?? this.title,
        detail: detail ?? this.detail,
        importance: (importance ?? this.importance).clamp(1, 10),
      );

  @override
  bool operator ==(Object other) =>
      other is ListingFeature &&
      other.title == title &&
      other.detail == detail &&
      other.importance == importance;

  @override
  int get hashCode => Object.hash(title, detail, importance);

  @override
  String toString() => '$title ($importance) — $detail';
}

/// How much following a tip would move the score.
enum AsoImpact {
  high('High'),
  medium('Medium');

  const AsoImpact(this.label);
  final String label;
}

/// What a tip is about.
enum AsoTipKind {
  keyword('Keyword'),
  copywriting('Copywriting'),
  visual('Visual');

  const AsoTipKind(this.label);
  final String label;
}

/// One way to make the listing rank or convert better.
@immutable
class AsoTip {
  const AsoTip(this.impact, this.kind, this.text);

  final AsoImpact impact;
  final AsoTipKind kind;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is AsoTip &&
      other.impact == impact &&
      other.kind == kind &&
      other.text == text;

  @override
  int get hashCode => Object.hash(impact, kind, text);

  @override
  String toString() => '[${impact.label}/${kind.label}] $text';
}

/// One screen of the planned listing: its headline, and a line under it when
/// there is something worth saying there.
@immutable
class PlanItem {
  const PlanItem(this.headline, {this.subtitle});

  final String headline;
  final String? subtitle;

  PlanItem copyWith({String? headline, String? subtitle, bool clear = false}) =>
      PlanItem(
        headline ?? this.headline,
        subtitle: clear ? null : (subtitle ?? this.subtitle),
      );

  @override
  bool operator ==(Object other) =>
      other is PlanItem &&
      other.headline == headline &&
      other.subtitle == subtitle;

  @override
  int get hashCode => Object.hash(headline, subtitle);

  @override
  String toString() => subtitle == null ? headline : '$headline | $subtitle';
}

/// The verdict a score earns, in the words the wizard shows.
String asoLabel(int score) => score >= 75
    ? 'Great'
    : score >= 50
    ? 'Good'
    : 'Needs work';

/// Everything the wizard's analysis step shows and the generator builds from.
@immutable
class ListingAnalysis {
  const ListingAnalysis({
    required this.appName,
    required this.category,
    required this.audience,
    required this.features,
    required this.usps,
    required this.keywords,
    required this.plan,
    required this.engine,
    this.asoScore = 0,
    this.tips = const [],
  });

  final String appName;
  final TemplateCategory category;

  /// Who the app is for, as one sentence.
  final String audience;

  final List<ListingFeature> features;

  /// What sets the app apart, as short phrases.
  final List<String> usps;

  /// The words and phrases people search the stores with, lower case.
  final List<String> keywords;

  /// One entry per screen, in listing order.
  final List<PlanItem> plan;

  /// 0–100. See [scoreListing].
  final int asoScore;
  final List<AsoTip> tips;

  /// What wrote this analysis — a model on the device, or the built-in rules.
  final AiEngine engine;

  String get asoVerdict => asoLabel(asoScore);

  ListingAnalysis copyWith({
    String? appName,
    TemplateCategory? category,
    String? audience,
    List<ListingFeature>? features,
    List<String>? usps,
    List<String>? keywords,
    List<PlanItem>? plan,
    int? asoScore,
    List<AsoTip>? tips,
    AiEngine? engine,
  }) => ListingAnalysis(
    appName: appName ?? this.appName,
    category: category ?? this.category,
    audience: audience ?? this.audience,
    features: features ?? this.features,
    usps: usps ?? this.usps,
    keywords: keywords ?? this.keywords,
    plan: plan ?? this.plan,
    asoScore: asoScore ?? this.asoScore,
    tips: tips ?? this.tips,
    engine: engine ?? this.engine,
  );

  /// This analysis with its score and tips worked out again from [description]
  /// and whatever the analysis now says — called after every edit, so the
  /// score answers to the listing the user is actually about to make.
  ListingAnalysis rescored(String description) {
    final (score, tips) = scoreListing(description, this);
    return copyWith(asoScore: score, tips: tips);
  }
}

// -----------------------------------------------------------------------------
// The ASO score
// -----------------------------------------------------------------------------

/// Verbs that promise the user a result. A listing that leads with them reads
/// as benefits; one that leads with nouns reads as a spec sheet.
const kBenefitVerbs = {
  'track',
  'save',
  'learn',
  'create',
  'discover',
  'find',
  'share',
  'plan',
  'manage',
  'organize',
  'organise',
  'build',
  'make',
  'edit',
  'play',
  'escape',
  'win',
  'beat',
  'listen',
  'watch',
  'explore',
  'enjoy',
  'boost',
  'improve',
  'grow',
  'connect',
  'stay',
  'get',
  'reach',
  'master',
  'protect',
  'scan',
  'design',
  'capture',
  'cook',
  'book',
  'budget',
  'stream',
  'relax',
  'sleep',
  'focus',
  'compete',
  'collect',
  'unlock',
  'solve',
  'sync',
  'automate',
  'record',
  'control',
  'customize',
  'customise',
  'download',
  'translate',
};

/// The listing's ASO score, 0–100, and what would raise it.
///
/// Rules rather than a model, on purpose: the score is shown next to the
/// user's own edits and has to move when they improve something, the same way
/// every time. What it rewards is what both stores' guidance does — a real
/// description, a name, a spread of keywords including longer phrases, enough
/// features to give every screenshot its own, and short benefit-led headlines.
(int, List<AsoTip>) scoreListing(String description, ListingAnalysis a) {
  final text = description.trim();
  final words = RegExp(
    r"[a-z0-9']+",
  ).allMatches(text.toLowerCase()).map((m) => m.group(0)!).toList();
  var score = 0;
  final tips = <AsoTip>[];

  // A description long enough to say what the app does, who for, and why.
  final length = text.length;
  score += length >= 2000
      ? 25
      : length >= 500
      ? 20
      : length >= 150
      ? 12
      : length >= kMinDescription
      ? 4
      : 0;
  if (length < 150) {
    tips.add(
      const AsoTip(
        AsoImpact.high,
        AsoTipKind.copywriting,
        'Describe the app in a few more sentences — what it does, who it is '
        'for and what makes it different. Both stores index these words.',
      ),
    );
  }

  // A name, short enough to show whole under the icon.
  final name = a.appName.trim();
  if (name.isNotEmpty) {
    score += 8;
    if (name.length <= 30) score += 2;
  } else {
    tips.add(
      const AsoTip(
        AsoImpact.high,
        AsoTipKind.keyword,
        'Give the app a name. The title is the strongest ranking signal in '
        'both stores.',
      ),
    );
  }

  // Features: one per screenshot is the goal.
  final features = a.features.length.clamp(0, kMaxFeatures);
  score += features * 3;
  if (features < 4) {
    tips.add(
      const AsoTip(
        AsoImpact.medium,
        AsoTipKind.copywriting,
        'List at least four features, so every screenshot can sell a '
        'different one.',
      ),
    );
  }

  // Keywords, and the longer phrases that are easier to rank for.
  final keywords = a.keywords.where((k) => k.trim().isNotEmpty).toList();
  score += keywords.length.clamp(0, 8) * 2;
  final phrases = keywords.where((k) => k.trim().contains(' ')).length;
  if (keywords.isNotEmpty && phrases / keywords.length >= 0.3) score += 5;
  if (keywords.length < 5) {
    tips.add(
      const AsoTip(
        AsoImpact.high,
        AsoTipKind.keyword,
        'Add more keywords — aim for five to ten, mixing single words with '
        'two-word phrases people actually search for.',
      ),
    );
  } else if (phrases == 0) {
    tips.add(
      AsoTip(
        AsoImpact.medium,
        AsoTipKind.keyword,
        'Add long-tail phrases such as "${keywords.first} app" — they face '
        'less competition than single words.',
      ),
    );
  }

  // The name carrying a keyword of its own ("Arrow Rush: Escape Game").
  if (name.isNotEmpty && keywords.length > 1) {
    final lowerName = name.toLowerCase();
    final carries = keywords
        .skip(1)
        .any(
          (k) => k.split(' ').any((w) => w.length > 3 && lowerName.contains(w)),
        );
    if (carries) {
      score += 5;
    } else {
      tips.add(
        AsoTip(
          AsoImpact.medium,
          AsoTipKind.keyword,
          'Consider a short keyword after the name, e.g. '
          '"$name: ${_titleCase(keywords[1])}".',
        ),
      );
    }
  }

  // Verbs that promise a result.
  final verbs = words.where(kBenefitVerbs.contains).toSet().length;
  score += verbs >= 3
      ? 10
      : verbs >= 1
      ? 5
      : 0;
  if (verbs < 2) {
    tips.add(
      const AsoTip(
        AsoImpact.medium,
        AsoTipKind.copywriting,
        'Lead with verbs that promise a result — "Track", "Save", '
        '"Discover" — rather than with what the screen contains.',
      ),
    );
  }

  // Headlines short enough to read at thumbnail size.
  final plan = a.plan.where((p) => p.headline.trim().isNotEmpty).toList();
  final long = plan.where((p) => _wordCount(p.headline) > 6).length;
  if (plan.isNotEmpty && long == 0) {
    score += 7;
  } else if (long > 0) {
    tips.add(
      const AsoTip(
        AsoImpact.medium,
        AsoTipKind.copywriting,
        'Keep every headline to six words or fewer — it has to read at '
        'thumbnail size in search results.',
      ),
    );
  }

  // Something that sets the app apart.
  if (a.usps.where((u) => u.trim().isNotEmpty).length >= 2) score += 4;

  // Visual advice applies to every listing; it fills the list when the copy is
  // already in good shape, so the user always has something to act on.
  tips.addAll(const [
    AsoTip(
      AsoImpact.high,
      AsoTipKind.visual,
      'Put the strongest benefit on the first two screenshots — most people '
      'never swipe past them.',
    ),
    AsoTip(
      AsoImpact.medium,
      AsoTipKind.visual,
      'Use one palette and one typeface across the set, so the screenshots '
      'read as a single story.',
    ),
  ]);

  // High-impact first, keeping each group's own order; never more than four.
  final ordered = [
    ...tips.where((t) => t.impact == AsoImpact.high),
    ...tips.where((t) => t.impact == AsoImpact.medium),
  ];
  // A thin description holds the whole listing back however well the rest is
  // filled in: the stores have nothing to index and the plan nothing to draw
  // on.
  final cap = length < 150
      ? 45
      : length < 500
      ? 80
      : 100;
  return (score.clamp(0, cap), ordered.take(4).toList());
}

int _wordCount(String s) =>
    s.trim().isEmpty ? 0 : s.trim().split(RegExp(r'\s+')).length;

String _titleCase(String s) => s
    .split(' ')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');
