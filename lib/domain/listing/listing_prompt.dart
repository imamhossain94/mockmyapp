/// Asking an on-device model for a listing analysis, and reading its answer.
///
/// The small models on phones and in browsers do not return reliable JSON, so
/// they are asked for one labelled line per fact — `FEATURE: … | … | 8` — which
/// survives the numbering, bullets and bold markers they add anyway. Whatever
/// the model leaves out or gets wrong is filled in from the built-in analysis,
/// so a half-good answer still makes a whole listing.
library;

import '../../data/services/on_device_ai.dart';
import '../models/screen_template.dart';
import 'listing_analysis.dart';
import 'listing_heuristics.dart';

/// What the model is told before the description.
final kListingInstructions =
    'You are an App Store Optimization expert. Read the app description and '
    'reply with labelled lines only, no other text:\n'
    'NAME: the app name\n'
    'CATEGORY: one of '
    '${TemplateCategory.values.map((c) => c.name).join(', ')}\n'
    'AUDIENCE: one sentence on who the app is for\n'
    'FEATURE: Title of two to five words | one-sentence benefit | importance '
    'from 1 to 10  (three to six FEATURE lines)\n'
    'USP: a short phrase on what makes the app unique  (two or three lines)\n'
    'KEYWORDS: comma-separated search keywords, single words and two-word '
    'phrases, lower case\n'
    'HEADLINE: a two-to-six word benefit-led screenshot headline | an optional '
    'subtitle of up to ten words  (one line per screenshot)\n'
    'Never mention prices, rankings or other apps. No emoji or hashtags.';

/// The request for one description.
String listingPrompt(
  String description, {
  String appName = '',
  int planLength = kDefaultPlanLength,
}) {
  final text = description.trim();
  // The on-device models' context is small; the start of a description is
  // where the app says what it is.
  final cut = text.length > 4000 ? '${text.substring(0, 4000)}…' : text;
  return [
    if (appName.trim().isNotEmpty) 'App name: ${appName.trim()}',
    'Write $planLength HEADLINE lines.',
    'Description:\n$cut',
  ].join('\n');
}

/// [reply] read into an analysis, with anything it lacks taken from
/// [fallback]; null when the reply has nothing usable at all.
ListingAnalysis? parseListingReply(
  String reply, {
  required ListingAnalysis fallback,
  required String description,
  required AiEngine engine,
  int planLength = kDefaultPlanLength,
  String appName = '',
}) {
  String? name;
  TemplateCategory? category;
  String? audience;
  final features = <ListingFeature>[];
  final usps = <String>[];
  final keywords = <String>[];
  final plan = <PlanItem>[];

  for (final raw in reply.split(RegExp(r'[\r\n]+'))) {
    var line = raw.trim();
    if (line.isEmpty) continue;
    line = line
        .replaceFirst(RegExp(r'^(\d+[.)]|[-*•–—])\s*'), '')
        .replaceAll('**', '')
        .replaceAll('__', '')
        .trim();
    final match = RegExp(r'^([A-Za-z ]{2,12}):\s*(.*)$').firstMatch(line);
    if (match == null) continue;
    final label = match.group(1)!.trim().toUpperCase();
    final value = _unquote(match.group(2)!);
    if (value.isEmpty) continue;
    switch (label) {
      case 'NAME' || 'APP NAME':
        name = value;
      case 'CATEGORY':
        category = _categoryOf(value);
      case 'AUDIENCE' || 'TARGET AUDIENCE':
        audience = value;
      case 'FEATURE':
        final parts = value.split('|').map(_unquote).toList();
        final title = parts.first;
        if (title.isEmpty || title.length > 60) continue;
        final importance = parts.length > 2
            ? int.tryParse(RegExp(r'\d+').stringMatch(parts[2]) ?? '')
            : null;
        features.add(
          ListingFeature(
            title: title,
            detail: parts.length > 1 ? parts[1] : '',
            importance: (importance ?? 7).clamp(1, 10),
          ),
        );
      case 'USP':
        if (value.length <= 80) usps.add(value);
      case 'KEYWORDS' || 'KEYWORD':
        for (final k in value.split(RegExp(r'[,;]'))) {
          final t = _unquote(k).toLowerCase();
          if (t.isNotEmpty && t.length <= 40 && !keywords.contains(t)) {
            keywords.add(t);
          }
        }
      case 'HEADLINE':
        final parts = value.split('|').map(_unquote).toList();
        final headline = parts.first;
        if (headline.isEmpty || headline.length > 60) continue;
        final subtitle = parts.length > 1 ? parts.sublist(1).join(' ') : '';
        plan.add(
          PlanItem(
            headline,
            subtitle: subtitle.isEmpty || subtitle.length > 90
                ? null
                : subtitle,
          ),
        );
    }
  }

  final usable = features.isNotEmpty || keywords.isNotEmpty || plan.isNotEmpty;
  if (!usable) return null;

  // Too few of anything is topped up from the rules rather than shown short.
  List<T> topUp<T>(List<T> own, List<T> extra, int min, int max) {
    final out = [...own];
    for (final e in extra) {
      if (out.length >= min) break;
      if (!out.contains(e)) out.add(e);
    }
    return out.take(max).toList();
  }

  final n = planLength.clamp(kMinPlanLength, kMaxPlanLength);
  return ListingAnalysis(
    appName: appName.trim().isNotEmpty
        ? appName.trim()
        : (name ?? fallback.appName),
    category: category ?? fallback.category,
    audience: audience ?? fallback.audience,
    features: topUp(features, fallback.features, kMinFeatures, kMaxFeatures),
    usps: topUp(usps, fallback.usps, 2, 4),
    keywords: topUp(keywords, fallback.keywords, 5, 12),
    plan: topUp(plan, fallback.plan, n, n),
    engine: engine,
  ).rescored(description);
}

TemplateCategory? _categoryOf(String value) {
  final v = value.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
  for (final c in TemplateCategory.values) {
    final label = c.label.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    if (v == c.name.toLowerCase() || v == label || v.startsWith(label)) {
      return c;
    }
  }
  return v.isEmpty ? null : guessCategory(value);
}

String _unquote(String s) =>
    s.trim().replaceAll(RegExp('^["“”\'‘’]+|["“”\'‘’]+\$'), '').trim();
