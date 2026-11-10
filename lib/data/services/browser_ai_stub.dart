import 'on_device_ai.dart';

/// Off the web there is no browser to ask.
(CaptionWriter?, TextTranslator) browserEngines() =>
    (null, const UnavailableTranslator());
