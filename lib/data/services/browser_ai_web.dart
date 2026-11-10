import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'browser_ai.dart';
import 'on_device_ai.dart';

/// Chrome's built-in AI, where the browser has it.
///
/// Both APIs are feature-detected on every call rather than once: they arrive
/// with browser updates, and a model can finish downloading while the page is
/// open. A browser without them gets the phrasebook and no translator — the
/// same as any other platform with no model.
(CaptionWriter?, TextTranslator) browserEngines() =>
    (_PromptWriter(), _BrowserTranslator());

bool _has(String name) {
  try {
    return globalContext.has(name);
  } catch (_) {
    return false;
  }
}

/// The API's availability words, old and new, as a [ModelState].
ModelState _stateOf(String? word) => switch (word) {
  'available' || 'readily' => ModelState.ready,
  'downloadable' ||
  'downloading' ||
  'after-download' => ModelState.needsDownload,
  _ => ModelState.unavailable,
};

// -----------------------------------------------------------------------------
// Prompt API
// -----------------------------------------------------------------------------

@JS('LanguageModel')
extension type _LanguageModel._(JSObject _) implements JSObject {
  external static JSPromise<JSString> availability();
  external static JSPromise<_LanguageModel> create(_ModelOptions options);
  external JSPromise<JSString> prompt(String input);
  external void destroy();
}

extension type _ModelOptions._(JSObject _) implements JSObject {
  external factory _ModelOptions({JSArray<_Message> initialPrompts});
}

extension type _Message._(JSObject _) implements JSObject {
  external factory _Message({String role, String content});
}

class _PromptWriter implements CaptionWriter, TextCompleter {
  @override
  Future<EngineStatus> writerStatus() async {
    if (!_has('LanguageModel')) {
      return const EngineStatus(AiEngine.browser, ModelState.unavailable);
    }
    try {
      final word = (await _LanguageModel.availability().toDart).toDart;
      return EngineStatus(AiEngine.browser, _stateOf(word));
    } catch (_) {
      return const EngineStatus(AiEngine.browser, ModelState.unavailable);
    }
  }

  @override
  Future<List<CaptionIdea>> write(CaptionBrief brief) async {
    _LanguageModel? session;
    try {
      session = await _LanguageModel.create(
        _ModelOptions(
          initialPrompts: [
            _Message(role: 'system', content: kCaptionInstructions),
          ].toJS,
        ),
      ).toDart;
      final reply = (await session.prompt(captionPrompt(brief)).toDart).toDart;
      final ideas = parseCaptionIdeas(reply, limit: brief.count);
      if (ideas.isEmpty) {
        throw const OnDeviceAiException(
          'The browser model did not come back with any captions.',
        );
      }
      return ideas;
    } on OnDeviceAiException {
      rethrow;
    } catch (e) {
      throw OnDeviceAiException('The browser model could not answer: $e');
    } finally {
      session?.destroy();
    }
  }

  @override
  Future<EngineStatus> completerStatus() => writerStatus();

  /// The same session the captions use, under the caller's own instructions.
  @override
  Future<String> complete({
    required String instructions,
    required String prompt,
  }) async {
    _LanguageModel? session;
    try {
      session = await _LanguageModel.create(
        _ModelOptions(
          initialPrompts: [
            _Message(role: 'system', content: instructions),
          ].toJS,
        ),
      ).toDart;
      return (await session.prompt(prompt).toDart).toDart;
    } catch (e) {
      throw OnDeviceAiException('The browser model could not answer: $e');
    } finally {
      session?.destroy();
    }
  }
}

// -----------------------------------------------------------------------------
// Translator API
// -----------------------------------------------------------------------------

@JS('Translator')
extension type _Translator._(JSObject _) implements JSObject {
  external static JSPromise<JSString> availability(_TranslatorOptions options);
  external static JSPromise<_Translator> create(_TranslatorOptions options);
  external JSPromise<JSString> translate(String input);
  external void destroy();
}

extension type _TranslatorOptions._(JSObject _) implements JSObject {
  external factory _TranslatorOptions({
    String sourceLanguage,
    String targetLanguage,
  });
}

class _BrowserTranslator implements TextTranslator {
  _TranslatorOptions _options(String from, String to) => _TranslatorOptions(
    sourceLanguage: browserLanguageTag(from),
    targetLanguage: browserLanguageTag(to),
  );

  @override
  Future<EngineStatus> translationStatus({
    required String from,
    required String to,
  }) async {
    if (!_has('Translator')) {
      return const EngineStatus(
        AiEngine.browser,
        ModelState.unavailable,
        reason: 'This browser has no built-in translator. Chrome does.',
      );
    }
    try {
      final word = (await _Translator.availability(
        _options(from, to),
      ).toDart).toDart;
      final state = _stateOf(word);
      return EngineStatus(
        AiEngine.browser,
        state,
        reason: state == ModelState.unavailable
            ? "The browser's translator does not offer this language pair."
            : null,
      );
    } catch (_) {
      return const EngineStatus(AiEngine.browser, ModelState.unavailable);
    }
  }

  @override
  Future<List<String>> translate(
    List<String> texts, {
    required String from,
    required String to,
  }) async {
    _Translator? translator;
    try {
      translator = await _Translator.create(_options(from, to)).toDart;
      return [
        for (final text in texts)
          text.trim().isEmpty
              ? text
              : (await translator.translate(text).toDart).toDart,
      ];
    } catch (e) {
      throw OnDeviceAiException('The browser could not translate: $e');
    } finally {
      translator?.destroy();
    }
  }
}
