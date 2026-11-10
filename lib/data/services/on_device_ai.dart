/// Language models and translators that run on the device, and the fallbacks
/// used where there are none.
///
/// MockMyApp's promise is that an unreleased app's screens never leave the
/// device, and the AI features keep it. Every engine here runs locally:
///
/// * **Apple Intelligence** through the Foundation Models framework, and
///   Apple's Translation framework and Vision, on iPhone, iPad and Mac;
/// * **Gemini Nano** through Android's AICore, ML Kit's translator and ML
///   Kit's text recognition, on Android;
/// * **the browser's built-in AI** — Chrome's Prompt and Translator APIs —
///   on the web.
///
/// A model or a language pack may have to be *downloaded* once, which is the
/// system fetching its own component; the user's words and pictures are never
/// what is sent. Where no engine exists at all, captions come from a built-in
/// phrasebook and translation says plainly that it is not available here —
/// nothing quietly falls back to a server.
///
/// The prompts, and the reading of what a model sends back, live here in Dart
/// rather than in each platform's code, so every engine is asked the same
/// question and every answer is cleaned up the same way — and both can be
/// tested without a model.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/models/locales.dart';
import 'browser_ai.dart';

// -----------------------------------------------------------------------------
// What is asked for
// -----------------------------------------------------------------------------

/// The voice a set of captions is written in.
enum CaptionTone {
  bold('Bold', 'confident and punchy, like a product launch'),
  friendly('Friendly', 'warm and plain-spoken, like a helpful friend'),
  premium('Premium', 'calm, precise and understated, like a luxury brand'),
  playful('Playful', 'light and witty, never silly');

  const CaptionTone(this.label, this.description);

  /// What the chip says.
  final String label;

  /// What the model is told.
  final String description;
}

/// Everything a caption writer is told about one screen.
@immutable
class CaptionBrief {
  const CaptionBrief({
    required this.appName,
    this.about = '',
    this.screenText = '',
    this.current = '',
    this.tone = CaptionTone.bold,
    this.language = kDefaultLanguage,
    this.count = 5,
  });

  /// What the project is called — usually the app's name.
  final String appName;

  /// What this screen shows, in the user's own words. May be empty.
  final String about;

  /// The words read off the screenshot, when it was read. May be empty.
  final String screenText;

  /// The headline as it stands, so a model can do better than it rather than
  /// repeat it.
  final String current;

  final CaptionTone tone;

  /// A store locale code — the language the captions come back in.
  final String language;

  /// How many to ask for.
  final int count;

  /// Whether there is anything to write from beyond the app's name.
  bool get hasSubject =>
      about.trim().isNotEmpty || screenText.trim().isNotEmpty;
}

/// One suggestion: a headline, and a line under it when the writer had one.
@immutable
class CaptionIdea {
  const CaptionIdea(this.headline, {this.subtitle});

  final String headline;
  final String? subtitle;

  @override
  bool operator ==(Object other) =>
      other is CaptionIdea &&
      other.headline == headline &&
      other.subtitle == subtitle;

  @override
  int get hashCode => Object.hash(headline, subtitle);

  @override
  String toString() => subtitle == null ? headline : '$headline | $subtitle';
}

/// Which engine is doing the work — shown to the user, so they know what
/// wrote their captions and whether it ran on their device.
enum AiEngine {
  appleIntelligence('Apple Intelligence'),
  geminiNano('Gemini Nano'),
  browser('Built-in browser AI'),
  appleTranslation('Apple Translate'),
  mlKit('ML Kit'),
  phrasebook('Built-in suggestions'),
  none('Not available');

  const AiEngine(this.label);

  final String label;
}

/// Whether an engine can be used right now.
enum ModelState {
  /// Ready to go.
  ready,

  /// Supported here, but the system has to fetch the model or the language
  /// pack first. That happens on first use.
  needsDownload,

  /// Not on this device — too old, switched off, or the language is not one
  /// the engine speaks.
  unavailable,
}

@immutable
class EngineStatus {
  const EngineStatus(this.engine, this.state, {this.reason});

  final AiEngine engine;
  final ModelState state;

  /// Why it is unavailable, in words fit for the user.
  final String? reason;

  bool get usable => state != ModelState.unavailable;
}

/// Thrown when an engine that said it was usable fails anyway.
class OnDeviceAiException implements Exception {
  const OnDeviceAiException(this.message);
  final String message;

  @override
  String toString() => message;
}

// -----------------------------------------------------------------------------
// The engines' contracts
// -----------------------------------------------------------------------------

/// Writes screenshot captions.
abstract interface class CaptionWriter {
  Future<EngineStatus> writerStatus();
  Future<List<CaptionIdea>> write(CaptionBrief brief);
}

/// Translates the words on a listing.
abstract interface class TextTranslator {
  /// Whether [from] → [to] can be translated here, both store locale codes.
  Future<EngineStatus> translationStatus({
    required String from,
    required String to,
  });

  /// [texts] in [to], in order. An empty string stays empty.
  Future<List<String>> translate(
    List<String> texts, {
    required String from,
    required String to,
  });
}

/// Answers a free-form request — the listing analysis of the AI screenshot
/// generator, which asks for more than captions and reads the reply itself.
///
/// The same models as [CaptionWriter], through the same calls; only the
/// instructions differ, and the caller parses the raw text.
abstract interface class TextCompleter {
  Future<EngineStatus> completerStatus();

  /// The model's reply to [prompt] under [instructions], as it came back.
  Future<String> complete({
    required String instructions,
    required String prompt,
  });
}

/// Reads the words off a screenshot.
abstract interface class ScreenReader {
  /// Whether this device can read at all.
  Future<bool> get canRead;

  /// The text on [image] — encoded image bytes — top to bottom, or an empty
  /// string when there is none or it cannot be read.
  Future<String> read(Uint8List image);
}

// -----------------------------------------------------------------------------
// Prompting, and reading answers
// -----------------------------------------------------------------------------

/// What every caption model is told before the brief — the house rules.
///
/// Mostly what the stores reject or what reads as spam in a listing: prices,
/// superlatives nobody can verify, emoji and hashtags. The format line is
/// what [parseCaptionIdeas] reads back.
const kCaptionInstructions =
    'You write captions for App Store and Google Play screenshots. '
    'A caption is a short headline of two to six words that says what the '
    'user gets, followed by an optional subtitle of up to ten words. '
    'Lead with the benefit, not the feature. Never mention prices, discounts, '
    'rankings, awards or other apps. No emoji, hashtags or quotation marks. '
    'Reply with one caption per line and nothing else, as: '
    'Headline | Subtitle';

/// The request for [brief], as one prompt.
///
/// The screen's own words are cut short: a model is better served by the
/// first few lines of a screen than by a wall of list items, and the on-device
/// models' context is small.
String captionPrompt(CaptionBrief brief) {
  final text = brief.screenText.trim();
  final screen = text.length > 600 ? '${text.substring(0, 600)}…' : text;
  final language = localeFor(brief.language).name;
  return [
    'App: ${brief.appName.trim().isEmpty ? 'an app' : brief.appName.trim()}',
    if (brief.about.trim().isNotEmpty) 'This screen: ${brief.about.trim()}',
    if (screen.isNotEmpty) 'Words visible on the screen:\n$screen',
    if (brief.current.trim().isNotEmpty)
      'Current caption, to improve on: ${brief.current.trim()}',
    'Tone: ${brief.tone.description}.',
    'Language: $language.',
    'Write ${brief.count} different captions.',
  ].join('\n');
}

/// The captions in [reply], however a model chose to lay them out.
///
/// Models number their lines, bullet them, quote them, bold them and add a
/// preamble — the house rules ask for none of it, and small on-device models
/// do it anyway. Each line is stripped back to its words; lines that are
/// obviously not captions (too long, a heading ending in a colon) are dropped,
/// and so are repeats.
List<CaptionIdea> parseCaptionIdeas(String reply, {int limit = 8}) {
  final ideas = <CaptionIdea>[];
  final seen = <String>{};
  for (final raw in reply.split(RegExp(r'[\r\n]+'))) {
    var line = raw.trim();
    if (line.isEmpty || line.endsWith(':')) continue;
    // "1. ", "2) ", "- ", "* ", "• "
    line = line.replaceFirst(RegExp(r'^(\d+[.)]|[-*•–—])\s*'), '');
    line = line.replaceAll('**', '').replaceAll('__', '');
    final parts = line.split(RegExp(r'\s+[|—–]\s+|\s*\|\s*'));
    String clean(String s) => s
        .trim()
        .replaceAll(RegExp('^["“”\'‘’]+|["“”\'‘’]+\$'), '')
        .replaceAll(
          RegExp(r'^(Headline|Subtitle)\s*:\s*', caseSensitive: false),
          '',
        )
        .trim();
    final headline = clean(parts.first);
    if (headline.isEmpty || headline.length > 60) continue;
    final subtitle = parts.length > 1 ? clean(parts.sublist(1).join(' ')) : '';
    if (!seen.add(headline.toLowerCase())) continue;
    ideas.add(
      CaptionIdea(
        headline,
        subtitle: subtitle.isEmpty || subtitle.length > 90 ? null : subtitle,
      ),
    );
    if (ideas.length >= limit) break;
  }
  return ideas;
}

/// [translated] broken over as many lines as [source] was.
///
/// A designer's line break is part of the layout — a two-line headline is
/// balanced on purpose — and translators flatten it. So the translation is
/// re-broken at word boundaries into the same number of lines, each about the
/// same share of the whole as its source line was. Scripts written without
/// spaces are left as they came: there is no word boundary to break at, and a
/// break in the wrong place is worse than none.
String rebreakLines(String source, String translated) {
  final lines = source.split('\n');
  final flat = translated.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim();
  if (lines.length < 2 || !flat.contains(' ')) return flat;

  final words = flat.split(RegExp(r'\s+'));
  if (words.length < lines.length) return flat;
  final total = lines.fold<int>(0, (n, l) => n + l.trim().length);
  if (total == 0) return flat;

  final out = <String>[];
  var start = 0;
  var sourceSoFar = 0;
  final flatLength = flat.length;
  for (var i = 0; i < lines.length - 1; i++) {
    sourceSoFar += lines[i].trim().length;
    final target = flatLength * sourceSoFar / total;
    // The word boundary nearest that share of the translation, leaving at
    // least one word for every line still to come.
    var end = start + 1;
    var bestGap = double.infinity;
    var length = words.take(start).fold<int>(0, (n, w) => n + w.length + 1);
    for (var j = start + 1; j <= words.length - (lines.length - 1 - i); j++) {
      length += words[j - 1].length + (j - 1 > start ? 1 : 0);
      final gap = (length - target).abs();
      if (gap < bestGap) {
        bestGap = gap;
        end = j;
      }
    }
    out.add(words.sublist(start, end).join(' '));
    start = end;
  }
  out.add(words.sublist(start).join(' '));
  return out.join('\n');
}

// -----------------------------------------------------------------------------
// The phrasebook — captions with no model at all
// -----------------------------------------------------------------------------

/// Captions assembled from the brief with no model: the fallback on Windows,
/// Linux, older phones and browsers without built-in AI.
///
/// Not a language model and not pretending to be one — it is labelled as
/// built-in suggestions wherever it is shown. What it does is take the
/// subject (the user's own description, or the most title-like words read off
/// the screen) and set it into headline patterns that work in listings, in
/// the chosen tone. Deterministic: the same brief always gives the same list,
/// so asking again after changing the tone is a real comparison.
class PhrasebookWriter implements CaptionWriter {
  const PhrasebookWriter();

  @override
  Future<EngineStatus> writerStatus() async =>
      const EngineStatus(AiEngine.phrasebook, ModelState.ready);

  @override
  Future<List<CaptionIdea>> write(CaptionBrief brief) async =>
      phrasebookIdeas(brief);
}

/// The phrasebook's captions for [brief]. Synchronous and pure — see
/// [PhrasebookWriter].
List<CaptionIdea> phrasebookIdeas(CaptionBrief brief) {
  final subject = _subjectOf(brief);
  final app = brief.appName.trim().isEmpty ? 'the app' : brief.appName.trim();
  // A subject that starts with a verb ("Track your spending") is an action;
  // anything else is a thing ("Spending insights").
  final words = subject.split(RegExp(r'\s+'));
  final first = words.first.toLowerCase();
  final isAction = _verbs.contains(first);
  final thing = isAction ? words.skip(1).join(' ') : subject;
  final thingLower = _lowerFirst(thing);
  final action = isAction ? _capitalise(subject) : 'Discover $thingLower';

  final patterns = switch (brief.tone) {
    CaptionTone.bold => [
      CaptionIdea(action, subtitle: 'All in $app.'),
      CaptionIdea(
        '${_capitalise(thing)}, sorted',
        subtitle: 'Less effort. Better results.',
      ),
      CaptionIdea('$action in seconds'),
      CaptionIdea('All your $thingLower. One place.'),
      CaptionIdea('${_capitalise(thing)} made effortless'),
      CaptionIdea('Take control of $thingLower'),
    ],
    CaptionTone.friendly => [
      CaptionIdea(
        '${_capitalise(thing)}, made easy',
        subtitle: '$app does the hard part.',
      ),
      CaptionIdea('$action, your way'),
      CaptionIdea('Say hello to simpler $thingLower'),
      CaptionIdea('Everything you need for $thingLower'),
      CaptionIdea('$action without the stress'),
      CaptionIdea('Your $thingLower, finally simple'),
    ],
    CaptionTone.premium => [
      CaptionIdea('${_capitalise(thing)}, refined'),
      CaptionIdea(
        'Considered $thingLower',
        subtitle: 'Designed down to the detail.',
      ),
      CaptionIdea('$action with clarity'),
      CaptionIdea('The calm way to $first ${isAction ? thingLower : 'it'}'),
      CaptionIdea('Precision for $thingLower'),
      CaptionIdea('${_capitalise(thing)}. Elevated.'),
    ],
    CaptionTone.playful => [
      CaptionIdea('${_capitalise(thing)}? Nailed it.'),
      CaptionIdea('$action like a pro', subtitle: 'No cape required.'),
      CaptionIdea('Your $thingLower just got fun'),
      CaptionIdea('Less faff, more $thingLower'),
      CaptionIdea('$action. Then relax.'),
      CaptionIdea('Meet your new favourite $thingLower'),
    ],
  };

  // Tidy: collapse the doubled spaces an empty subject leaves, and drop any
  // headline the pattern made too long to set.
  final seen = <String>{};
  return [
    for (final idea in patterns)
      if (idea.headline.replaceAll(RegExp(r'\s+'), ' ').trim() case final h
          when h.length <= 48 && seen.add(h.toLowerCase()))
        CaptionIdea(h, subtitle: idea.subtitle),
  ].take(brief.count).toList();
}

/// What the captions are about: the user's own words first, then the most
/// title-like line on the screen, then the app itself.
String _subjectOf(CaptionBrief brief) {
  final about = brief.about.trim().replaceAll(RegExp(r'[.!?]+$'), '');
  if (about.isNotEmpty) {
    final words = about.split(RegExp(r'\s+'));
    return words.take(6).join(' ');
  }
  // A screen's title is short, is not a number, and is not UI chrome.
  for (final line in brief.screenText.split('\n')) {
    final t = line.trim();
    if (t.length < 3 || t.length > 28) continue;
    if (RegExp(r'^[\d\s.,:%$€£¥+-]+$').hasMatch(t)) continue;
    if (_chrome.contains(t.toLowerCase())) continue;
    if (RegExp(r'^\d{1,2}:\d{2}').hasMatch(t)) continue;
    return t;
  }
  return 'everything in ${brief.appName.trim().isEmpty ? 'one app' : brief.appName.trim()}';
}

String _capitalise(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

String _lowerFirst(String s) {
  if (s.isEmpty) return s;
  // An acronym or a proper name keeps its capital.
  if (s.length > 1 &&
      s[1].toUpperCase() == s[1] &&
      s[1] != s[1].toLowerCase()) {
    return s;
  }
  return '${s[0].toLowerCase()}${s.substring(1)}';
}

/// Verbs a subject can open with — "Track spending", "Plan trips".
const _verbs = {
  'track',
  'plan',
  'share',
  'edit',
  'find',
  'create',
  'build',
  'make',
  'manage',
  'organize',
  'organise',
  'save',
  'send',
  'learn',
  'discover',
  'book',
  'order',
  'listen',
  'watch',
  'read',
  'write',
  'design',
  'scan',
  'sync',
  'split',
  'budget',
  'record',
  'capture',
  'chat',
  'meet',
  'train',
  'cook',
  'shop',
  'explore',
  'monitor',
  'measure',
  'control',
  'connect',
  'store',
  'protect',
  'backup',
  'back',
  'translate',
  'draw',
  'play',
  'stream',
  'invest',
  'pay',
  'sell',
  'buy',
  'compare',
  'schedule',
  'remind',
  'focus',
  'relax',
  'sleep',
  'meditate',
  'journal',
  'log',
  'boost',
  'grow',
  'automate',
};

/// Status-bar and tab-bar words a screenshot is full of and a caption is
/// never about.
const _chrome = {
  'home',
  'search',
  'settings',
  'profile',
  'back',
  'done',
  'cancel',
  'edit',
  'more',
  'menu',
  'next',
  'ok',
  'save',
  'close',
  'today',
  'lte',
  '5g',
  'wi-fi',
};

// -----------------------------------------------------------------------------
// Engines with no model
// -----------------------------------------------------------------------------

/// A translator for a device with none, which says so rather than guessing.
class UnavailableTranslator implements TextTranslator {
  const UnavailableTranslator([
    this.reason = 'Automatic translation is not available on this device.',
  ]);

  final String reason;

  @override
  Future<EngineStatus> translationStatus({
    required String from,
    required String to,
  }) async =>
      EngineStatus(AiEngine.none, ModelState.unavailable, reason: reason);

  @override
  Future<List<String>> translate(
    List<String> texts, {
    required String from,
    required String to,
  }) => Future.error(OnDeviceAiException(reason));
}

/// A reader for a device that cannot read screenshots.
class UnavailableScreenReader implements ScreenReader {
  const UnavailableScreenReader();

  @override
  Future<bool> get canRead async => false;

  @override
  Future<String> read(Uint8List image) async => '';
}

// -----------------------------------------------------------------------------
// The native engines — Apple Intelligence and Gemini Nano
// -----------------------------------------------------------------------------

/// The platform's own models, through `mockmyapp/ai`.
///
/// See `OnDeviceAiBridge.swift` and `OnDeviceAiBridge.kt`. Every method
/// answers in plain maps and strings, so this class is the whole of the Dart
/// side and the platform code stays a thin wrapper round each framework.
class NativeOnDeviceAi
    implements CaptionWriter, TextTranslator, ScreenReader, TextCompleter {
  NativeOnDeviceAi({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('mockmyapp/ai');

  final MethodChannel _channel;

  /// What the platform said the last time it was asked, so the caption sheet
  /// can offer the model it has without a second round trip.
  EngineStatus? _writerStatus;

  static EngineStatus _statusFrom(
    Map<String, dynamic>? map,
    AiEngine fallback,
  ) {
    if (map == null) {
      return EngineStatus(fallback, ModelState.unavailable);
    }
    final engine =
        AiEngine.values.where((e) => e.name == map['engine']).firstOrNull ??
        fallback;
    final state =
        ModelState.values.where((s) => s.name == map['state']).firstOrNull ??
        ModelState.unavailable;
    return EngineStatus(engine, state, reason: map['reason'] as String?);
  }

  @override
  Future<EngineStatus> writerStatus() async {
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>(
        'captionStatus',
      );
      return _writerStatus = _statusFrom(map, AiEngine.none);
    } on PlatformException catch (e) {
      return EngineStatus(
        AiEngine.none,
        ModelState.unavailable,
        reason: e.message,
      );
    } on MissingPluginException {
      return const EngineStatus(AiEngine.none, ModelState.unavailable);
    }
  }

  @override
  Future<List<CaptionIdea>> write(CaptionBrief brief) async {
    try {
      final reply = await _channel.invokeMethod<String>('writeCaptions', {
        'instructions': kCaptionInstructions,
        'prompt': captionPrompt(brief),
      });
      final ideas = parseCaptionIdeas(reply ?? '', limit: brief.count);
      if (ideas.isEmpty) {
        throw const OnDeviceAiException(
          'The model did not come back with any captions. Try again.',
        );
      }
      return ideas;
    } on PlatformException catch (e) {
      throw OnDeviceAiException(e.message ?? 'The model could not answer.');
    }
  }

  /// The engine the last [writerStatus] reported.
  AiEngine? get writerEngine => _writerStatus?.engine;

  @override
  Future<EngineStatus> completerStatus() => writerStatus();

  /// Through `writeCaptions`, which hands its instructions and prompt to the
  /// model untouched and returns the raw reply — the platform code has no idea
  /// it is writing captions, so it serves any request of the same shape.
  @override
  Future<String> complete({
    required String instructions,
    required String prompt,
  }) async {
    try {
      final reply = await _channel.invokeMethod<String>('writeCaptions', {
        'instructions': instructions,
        'prompt': prompt,
      });
      return reply ?? '';
    } on PlatformException catch (e) {
      throw OnDeviceAiException(e.message ?? 'The model could not answer.');
    } on MissingPluginException {
      throw const OnDeviceAiException('There is no model on this device.');
    }
  }

  @override
  Future<EngineStatus> translationStatus({
    required String from,
    required String to,
  }) async {
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>(
        'translationStatus',
        {'from': from, 'to': to},
      );
      return _statusFrom(map, AiEngine.none);
    } on PlatformException catch (e) {
      return EngineStatus(
        AiEngine.none,
        ModelState.unavailable,
        reason: e.message,
      );
    } on MissingPluginException {
      return const EngineStatus(AiEngine.none, ModelState.unavailable);
    }
  }

  @override
  Future<List<String>> translate(
    List<String> texts, {
    required String from,
    required String to,
  }) async {
    if (texts.every((t) => t.trim().isEmpty)) return [...texts];
    try {
      final out = await _channel.invokeListMethod<String>('translate', {
        'texts': texts,
        'from': from,
        'to': to,
      });
      if (out == null || out.length != texts.length) {
        throw const OnDeviceAiException(
          'The translator lost some of the text.',
        );
      }
      return out;
    } on PlatformException catch (e) {
      throw OnDeviceAiException(e.message ?? 'Translation failed.');
    }
  }

  @override
  Future<bool> get canRead async {
    try {
      return await _channel.invokeMethod<bool>('canReadText') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<String> read(Uint8List image) async {
    try {
      return await _channel.invokeMethod<String>('readText', {
            'image': image,
          }) ??
          '';
    } on PlatformException {
      return '';
    } on MissingPluginException {
      return '';
    }
  }
}

/// A writer that uses the device's model when there is one and the
/// phrasebook when there is not — the only writer the app ever holds.
///
/// Decided per request rather than once at start-up: Apple Intelligence can be
/// switched on in Settings while the app is open, and a model finishes
/// downloading in the background.
class CaptionAssistant implements CaptionWriter {
  CaptionAssistant(this.model, {this.fallback = const PhrasebookWriter()});

  /// The device's own model, or null where there is none.
  final CaptionWriter? model;
  final CaptionWriter fallback;

  @override
  Future<EngineStatus> writerStatus() async {
    final m = model;
    if (m != null) {
      final s = await m.writerStatus();
      if (s.usable) return s;
    }
    return fallback.writerStatus();
  }

  @override
  Future<List<CaptionIdea>> write(CaptionBrief brief) async {
    final m = model;
    if (m != null && (await m.writerStatus()).usable) {
      try {
        return await m.write(brief);
      } on OnDeviceAiException {
        // A model that says it is ready and then fails — asleep, busy, out of
        // memory — should not leave the user with nothing.
      }
    }
    return fallback.write(brief);
  }
}

/// The engines this platform has.
///
/// One place for the platform question, so nothing else asks it.
///
/// [completer] is null where there is no model at all; callers fall back to
/// their own rules there, as the caption writer falls back to the phrasebook.
({
  CaptionWriter writer,
  TextTranslator translator,
  ScreenReader reader,
  TextCompleter? completer,
})
platformAi() {
  if (kIsWeb) {
    final browser = BrowserAi();
    return (
      writer: CaptionAssistant(browser.writer),
      translator: browser.translator,
      reader: const UnavailableScreenReader(),
      completer: browser.completer,
    );
  }
  if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
    final native = NativeOnDeviceAi();
    return (
      writer: CaptionAssistant(native),
      translator: native,
      reader: native,
      completer: native,
    );
  }
  return (
    writer: CaptionAssistant(null),
    translator: const UnavailableTranslator(
      'Automatic translation needs the iPhone, iPad, Mac, Android or web '
      'version of MockMyApp.',
    ),
    reader: const UnavailableScreenReader(),
    completer: null,
  );
}
