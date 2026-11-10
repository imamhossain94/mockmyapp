import 'browser_ai_stub.dart'
    if (dart.library.js_interop) 'browser_ai_web.dart'
    as impl;
import 'on_device_ai.dart';

/// The browser's built-in AI: Chrome's Prompt API for captions and its
/// Translator API for translation, both of which run in the browser on the
/// user's machine.
///
/// Off the web — and in a browser without them — there is no model here: the
/// writer is null, which hands captions to the phrasebook, and the translator
/// says it is unavailable.
class BrowserAi {
  BrowserAi() : _engines = impl.browserEngines();

  final (CaptionWriter?, TextTranslator) _engines;

  CaptionWriter? get writer => _engines.$1;

  /// The same Prompt API session, for requests that are not captions — null
  /// wherever [writer] is.
  TextCompleter? get completer => switch (_engines.$1) {
    final TextCompleter completer => completer,
    _ => null,
  };
  TextTranslator get translator => _engines.$2;
}

/// The Translator API's name for a store locale: a bare language except where
/// the script is the whole difference.
String browserLanguageTag(String storeCode) => switch (storeCode) {
  'zh-Hans' => 'zh',
  'zh-Hant' => 'zh-Hant',
  'nb-NO' => 'nb',
  _ => storeCode.split('-').first,
};
