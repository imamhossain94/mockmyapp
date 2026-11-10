/// Drafting store copy with the model on this device — Apple Intelligence,
/// Gemini Nano, the browser's built-in AI — and the built-in rules where
/// there is none.
///
/// The small models are asked for what they do well: the short fields (name,
/// subtitle, keywords, a promotional line, a short description) and the
/// opening of the description, as labelled lines rather than JSON, which they
/// do not return reliably. Android's model stops at a few hundred tokens, so
/// a whole 4,000-character description is never asked for: the rules lay out
/// the rest — features, what sets the app apart — from the brief, under the
/// model's opening. Whatever the model leaves out or gets wrong is taken from
/// the rules, and every field passes [fitDraftField] on its way out, so a
/// model's slip never reaches the page longer than its limit or naming
/// another platform in Apple copy.
library;

import 'package:flutter/foundation.dart';

import '../../data/services/on_device_ai.dart';
import '../models/locales.dart';
import 'copy_draft.dart';
import 'store_limits.dart';

/// A draft for one store in one language, and what wrote it.
@immutable
class CopyDraftResult {
  const CopyDraftResult(this.fields, {required this.engine, this.note});

  /// Field id → text, only the fields this draft wrote.
  final Map<String, String> fields;

  /// Who wrote it: a model on the device, or the built-in rules.
  final AiEngine engine;

  /// Something to say beside the result — that the device's model did not
  /// answer and the rules stood in, say.
  final String? note;
}

/// The labelled line each role is asked for.
const _labels = {
  CopyRole.name: 'NAME',
  CopyRole.subtitle: 'SUBTITLE',
  CopyRole.keywords: 'KEYWORDS',
  CopyRole.promo: 'PROMO',
  CopyRole.short: 'SHORT',
  CopyRole.long: 'INTRO',
  CopyRole.release: 'WHATSNEW',
};

/// What the model is told for [fields] of [store], before the brief.
String storeCopyInstructions(CopyStore store, List<CopyFieldSpec> fields) {
  final lines = <String>[];
  final seen = <CopyRole>{};
  for (final field in fields) {
    final role = roleOf(field);
    final label = _labels[role];
    if (label == null || !seen.add(role)) continue;
    final size = field.unit == CopyUnit.bytes
        ? 'at most ${field.limit} bytes'
        : 'at most ${field.limit} characters';
    lines.add(switch (role) {
      CopyRole.name => '$label: the app name for the listing, $size',
      CopyRole.subtitle => '$label: one line under the name, $size',
      CopyRole.keywords =>
        '$label: comma-separated search words with no spaces after the '
            'commas, $size, none already in the name or subtitle',
      CopyRole.promo => '$label: one sentence that makes people curious, $size',
      CopyRole.short => '$label: one sentence on what the app does, $size',
      CopyRole.long =>
        '$label: the first two or three sentences of the description',
      CopyRole.release => '$label: one sentence on what is new in this version',
      _ => '',
    });
  }
  return [
    'You write store listing copy for ${store.label}. Reply with labelled '
        'lines only, no other text:',
    ...lines,
    'Never mention prices, discounts, rankings, awards, other apps or other '
        'platforms. No emoji, hashtags or links.',
  ].join('\n');
}

/// The request for [source] in [language].
String storeCopyPrompt(
  DraftSource source, {
  required String language,
  CaptionTone tone = CaptionTone.bold,
}) {
  final description = source.description.length > 1500
      ? '${source.description.substring(0, 1500)}…'
      : source.description;
  return [
    'App: ${source.name}',
    if (description.isNotEmpty) 'What it does: $description',
    if (source.audience.isNotEmpty) 'Who it is for: ${source.audience}',
    if (source.features.isNotEmpty)
      'Features: ${source.features.take(6).map((f) => f.title).join('; ')}',
    if (source.keywords.isNotEmpty)
      'Search words: ${source.keywords.take(12).join(', ')}',
    'Tone: ${tone.description}.',
    'Language: ${localeFor(language).name}.',
  ].join('\n');
}

/// [reply] read into role → text; roles the reply has nothing usable for are
/// left out.
Map<CopyRole, String> parseStoreCopyReply(String reply) {
  final byLabel = {for (final e in _labels.entries) e.value: e.key};
  final out = <CopyRole, String>{};
  for (final raw in reply.split(RegExp(r'[\r\n]+'))) {
    // Bold markers first: "**SUBTITLE:** …" would otherwise lose one star
    // to the bullet rule and keep the other in front of its label.
    final line = raw
        .replaceAll('**', '')
        .replaceAll('__', '')
        .trim()
        .replaceFirst(RegExp(r'^(\d+[.)]|[-*•–—])\s*'), '')
        .trim();
    final match = RegExp(r'^([A-Za-z ]{3,12}):\s*(.*)$').firstMatch(line);
    if (match == null) continue;
    final label = match.group(1)!.trim().toUpperCase().replaceAll(' ', '');
    final role =
        byLabel[label] ?? (label == "WHAT'SNEW" ? CopyRole.release : null);
    final value = match
        .group(2)!
        .trim()
        .replaceAll(RegExp('^["“”\'‘’]+|["“”\'‘’]+\$'), '')
        .trim();
    if (role == null || value.isEmpty || out.containsKey(role)) continue;
    out[role] = value;
  }
  return out;
}

/// The device's model's answer laid over the rules' draft, field by field.
///
/// In the brief's own language the rules fill whatever the model did not
/// write, and its opening goes on top of the rules' description. In another
/// language only what the model wrote is used: the rules write in the
/// brief's words, and an English feature list under a German opening is
/// worse than a short German description.
Map<String, String> mergeDeviceDraft(
  CopyStore store,
  DraftSource source,
  Map<CopyRole, String> written, {
  required bool inBriefLanguage,
  Set<String>? only,
  int variant = 0,
}) {
  final rules = inBriefLanguage
      ? draftStoreCopy(store, source, only: only, variant: variant)
      : const <String, String>{};
  final out = <String, String>{};
  for (final field in store.allFields) {
    if (only != null && !only.contains(field.id)) continue;
    final role = roleOf(field);
    final mine = written[role];
    String? text;
    if (role == CopyRole.long && mine != null) {
      final rest = (rules[field.id] ?? '').split('\n\n').skip(1).join('\n\n');
      text = rest.isEmpty ? mine : '$mine\n\n$rest';
    } else {
      text = mine ?? rules[field.id];
    }
    if (text == null || text.trim().isEmpty) continue;
    final fitted = fitDraftField(
      store,
      field,
      text,
      name: out['name'] ?? '',
      subtitle: out['subtitle'] ?? '',
      appName: source.name,
    );
    if (fitted.isNotEmpty) out[field.id] = fitted;
  }
  return out;
}

/// Drafts with the device's model when it can, and the built-in rules when it
/// cannot — decided per request, like the caption writer: a model can finish
/// downloading, or be switched on, while the page is open.
class DeviceCopyWriter {
  const DeviceCopyWriter(this.model);

  /// The device's model, or null where there is none.
  final TextCompleter? model;

  /// Who [draft] would use right now.
  Future<AiEngine> engine() async {
    final m = model;
    if (m != null) {
      final status = await m.completerStatus();
      if (status.usable) return status.engine;
    }
    return AiEngine.phrasebook;
  }

  /// [store]'s copy in [language], from [brief].
  ///
  /// [inBriefLanguage] says whether [language] is the one the brief is
  /// written in — the project's default. The rules write only in that one.
  Future<CopyDraftResult> draft(
    CopyStore store,
    DraftSource source, {
    required String language,
    required bool inBriefLanguage,
    CaptionTone tone = CaptionTone.bold,
    Set<String>? only,
    int variant = 0,
  }) async {
    final m = model;
    String? note;
    if (m != null) {
      try {
        final status = await m.completerStatus();
        if (status.usable) {
          final fields = [
            for (final f in store.allFields)
              if (only == null || only.contains(f.id)) f,
          ];
          final reply = await m.complete(
            instructions: storeCopyInstructions(store, fields),
            prompt: storeCopyPrompt(source, language: language, tone: tone),
          );
          final written = parseStoreCopyReply(reply);
          if (written.isNotEmpty) {
            return CopyDraftResult(
              mergeDeviceDraft(
                store,
                source,
                written,
                inBriefLanguage: inBriefLanguage,
                only: only,
                variant: variant,
              ),
              engine: status.engine,
            );
          }
          note =
              '${status.engine.label} came back with nothing usable, so these '
              'are the built-in suggestions.';
        }
      } on OnDeviceAiException catch (error) {
        note =
            "The AI on this device couldn't answer (${error.message}), so "
            'these are the built-in suggestions.';
      }
    }
    if (!inBriefLanguage) {
      throw const OnDeviceAiException(
        'The built-in suggestions are written in your brief’s language. '
        'Draft that language first, then translate it.',
      );
    }
    return CopyDraftResult(
      draftStoreCopy(store, source, only: only, variant: variant),
      engine: AiEngine.phrasebook,
      note: note,
    );
  }
}
