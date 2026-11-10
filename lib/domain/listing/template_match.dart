/// Which of the catalog's listings suits an app, and which screenshot belongs
/// on which screen.
library;

import '../models/screen_template.dart';

/// One template, with how well it suits the app and why.
class TemplateMatch {
  const TemplateMatch(this.template, this.score, this.reason);

  final ScreenTemplate template;

  /// 0–100.
  final int score;

  /// One line the wizard shows under the name.
  final String reason;
}

/// Kinds of app whose listings borrow each other's looks well, and how well.
///
/// Symmetric in spirit but written one way round, because "a game listing
/// suits an entertainment app" and the reverse are not equally true.
const _related = <TemplateCategory, Map<TemplateCategory, int>>{
  TemplateCategory.games: {
    TemplateCategory.entertainment: 85,
    TemplateCategory.education: 65,
  },
  TemplateCategory.entertainment: {
    TemplateCategory.games: 80,
    TemplateCategory.music: 80,
    TemplateCategory.photoVideo: 75,
  },
  TemplateCategory.music: {
    TemplateCategory.entertainment: 85,
    TemplateCategory.photoVideo: 70,
  },
  TemplateCategory.finance: {
    TemplateCategory.business: 85,
    TemplateCategory.productivity: 75,
  },
  TemplateCategory.shopping: {
    TemplateCategory.lifestyle: 80,
    TemplateCategory.food: 70,
  },
  TemplateCategory.food: {
    TemplateCategory.lifestyle: 80,
    TemplateCategory.health: 70,
    TemplateCategory.shopping: 65,
  },
  TemplateCategory.travel: {
    TemplateCategory.lifestyle: 75,
    TemplateCategory.utilities: 70,
  },
  TemplateCategory.health: {
    TemplateCategory.lifestyle: 80,
    TemplateCategory.food: 70,
  },
  TemplateCategory.education: {
    TemplateCategory.productivity: 80,
    TemplateCategory.games: 65,
  },
  TemplateCategory.photoVideo: {
    TemplateCategory.entertainment: 80,
    TemplateCategory.social: 70,
    TemplateCategory.utilities: 65,
  },
  TemplateCategory.social: {
    TemplateCategory.lifestyle: 80,
    TemplateCategory.entertainment: 70,
    TemplateCategory.photoVideo: 70,
  },
  TemplateCategory.productivity: {
    TemplateCategory.business: 85,
    TemplateCategory.utilities: 80,
    TemplateCategory.education: 70,
  },
  TemplateCategory.lifestyle: {
    TemplateCategory.social: 80,
    TemplateCategory.health: 75,
    TemplateCategory.shopping: 70,
  },
  TemplateCategory.business: {
    TemplateCategory.productivity: 85,
    TemplateCategory.finance: 80,
  },
  TemplateCategory.utilities: {
    TemplateCategory.productivity: 80,
    TemplateCategory.photoVideo: 65,
    TemplateCategory.travel: 65,
  },
};

/// [templates] ranked for an app of [category], best first.
///
/// The category decides most of it — a listing designed for the same kind of
/// app is 95%, a related kind 65–85%, anything else a neutral 40%. A listing
/// styled for the other store loses a little (its mockup will not be used),
/// and one whose name or blurb shares a word with the app's [keywords] gains
/// a little. Ties keep the catalog's own order.
List<TemplateMatch> rankTemplates(
  TemplateCategory category,
  List<ScreenTemplate> templates, {
  TemplatePlatform? platform,
  List<String> keywords = const [],
}) {
  final words = {
    for (final k in keywords)
      for (final w in k.toLowerCase().split(RegExp(r'\s+')))
        if (w.length > 3) w,
  };
  final ranked = <(int, TemplateMatch)>[];
  for (final (i, t) in templates.indexed) {
    var score = 40;
    var reason = 'A neutral look that suits most apps';
    if (t.category == category) {
      score = 95;
      reason = 'Designed for ${category.label} apps';
    } else if (t.category case final other?) {
      final related = _related[category]?[other];
      if (related != null) {
        score = related;
        reason = '${other.label} is close to ${category.label}';
      } else {
        reason = 'A ${other.label} look — a different kind of app';
      }
    }
    if (platform != null && !t.framesFor(platform)) {
      score -= 8;
      reason =
          '$reason · styled for ${t.platforms.map((p) => p.label).join(' & ')}';
    }
    final named = '${t.name} ${t.blurb}'.toLowerCase();
    if (words.any(named.contains)) score += 4;
    ranked.add((i, TemplateMatch(t, score.clamp(0, 100), reason)));
  }
  ranked.sort((a, b) {
    final byScore = b.$2.score.compareTo(a.$2.score);
    return byScore != 0 ? byScore : a.$1.compareTo(b.$1);
  });
  return [for (final (_, m) in ranked) m];
}

/// The order to put [screenTexts] in so each lands on the plan item whose
/// words it shares most with — the screenshot of the playlist under the
/// headline about playlists.
///
/// Returns indices into [screenTexts]. Greedy, best overlap first; a
/// screenshot that shares nothing with any headline keeps its relative place
/// among the leftovers, so a set with no readable text comes back in the
/// order it went in.
List<int> orderScreenshotsByPlan(
  List<String> headlines,
  List<String> screenTexts,
) {
  Set<String> wordsOf(String s) => {
    for (final m in RegExp(r'[a-z0-9]+').allMatches(s.toLowerCase()))
      if (m.group(0)!.length > 3) _stem(m.group(0)!),
  };
  final plan = [for (final h in headlines) wordsOf(h)];
  final shots = [for (final t in screenTexts) wordsOf(t)];

  final pairs = <(int, int, int)>[];
  for (var p = 0; p < plan.length; p++) {
    for (var s = 0; s < shots.length; s++) {
      final overlap = plan[p].intersection(shots[s]).length;
      if (overlap > 0) pairs.add((overlap, p, s));
    }
  }
  pairs.sort((a, b) {
    final byOverlap = b.$1.compareTo(a.$1);
    if (byOverlap != 0) return byOverlap;
    final byPlan = a.$2.compareTo(b.$2);
    return byPlan != 0 ? byPlan : a.$3.compareTo(b.$3);
  });

  final slot = List<int?>.filled(plan.length, null);
  final used = <int>{};
  for (final (_, p, s) in pairs) {
    if (slot[p] != null || used.contains(s)) continue;
    slot[p] = s;
    used.add(s);
  }
  final rest = [
    for (var s = 0; s < shots.length; s++)
      if (!used.contains(s)) s,
  ];
  final order = <int>[];
  for (var p = 0; p < plan.length; p++) {
    final s = slot[p] ?? (rest.isEmpty ? null : rest.removeAt(0));
    if (s != null) order.add(s);
  }
  // More screenshots than screens: the extras follow, in their own order.
  order.addAll(rest);
  return order;
}

String _stem(String w) => w.length > 4 && w.endsWith('s') && !w.endsWith('ss')
    ? w.substring(0, w.length - 1)
    : w;
