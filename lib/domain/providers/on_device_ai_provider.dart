import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/on_device_ai.dart';

/// The device's AI engines, chosen once per app run.
///
/// Under `flutter test` nothing native is asked: a test VM on a Mac would
/// otherwise get the Apple bridge and talk to a channel with nobody on the
/// other end. Tests that want a model override the providers below.
final _engines = Provider((ref) {
  if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) {
    return (
      writer: CaptionAssistant(null) as CaptionWriter,
      translator: const UnavailableTranslator() as TextTranslator,
      reader: const UnavailableScreenReader() as ScreenReader,
      completer: null as TextCompleter?,
    );
  }
  return platformAi();
});

/// Writes captions: the device's model where there is one, the phrasebook
/// where there is not.
final captionWriterProvider = Provider<CaptionWriter>(
  (ref) => ref.watch(_engines).writer,
);

/// Translates captions on the device, or says it cannot.
final translatorProvider = Provider<TextTranslator>(
  (ref) => ref.watch(_engines).translator,
);

/// Reads the words off a screenshot on the device, where it can.
final screenReaderProvider = Provider<ScreenReader>(
  (ref) => ref.watch(_engines).reader,
);

/// Answers free-form requests with the device's model, or null where there is
/// none — the AI screenshot generator then uses its built-in analysis.
final textCompleterProvider = Provider<TextCompleter?>(
  (ref) => ref.watch(_engines).completer,
);
