/// Translating a store listing with the device's own translator, where it
/// has one.
///
/// A translation is stored per language like any other copy. It is never cut
/// on the device to fit: a German description that runs past its limit is
/// kept whole and the field says so, because a sentence chopped by a machine
/// is worse than one the person shortens. The one exception is Apple's
/// keyword field, which is a list rather than prose — it is packed again,
/// dropping the last keywords.
library;

import '../../data/services/on_device_ai.dart';
import 'copy_lint.dart' show tidyAppleKeywords;
import 'copy_text.dart';
import 'store_limits.dart';

/// Translates a listing with the device's own translator — Apple Translate,
/// ML Kit, the browser's — line by line, so paragraphs and bullets keep their
/// shape, and keywords one at a time, so a translator never runs two of them
/// together.
class DeviceCopyTranslator {
  const DeviceCopyTranslator(this.translator);

  final TextTranslator translator;

  Future<EngineStatus> status({required String from, required String to}) =>
      translator.translationStatus(from: from, to: to);

  /// [fields] of [store], from [from] into [to].
  Future<Map<String, String>> translate(
    CopyStore store,
    Map<String, String> fields, {
    required String from,
    required String to,
    String appName = '',
  }) async {
    // Every piece of text to translate, in one list for one call, and how to
    // put each field back together from its pieces.
    final pieces = <String>[];
    final rebuild = <String, String Function(List<String> out)>{};
    for (final spec in store.allFields) {
      final text = fields[spec.id];
      if (text == null || text.trim().isEmpty) continue;
      final start = pieces.length;
      if (spec.keywords) {
        final terms = keywordTerms(text);
        pieces.addAll(terms);
        rebuild[spec.id] = (out) =>
            out.sublist(start, start + terms.length).join(',');
      } else {
        final lines = text.split('\n');
        // A bullet's mark stays the device's, not the translator's: "• " is
        // put back on the translated words.
        // The whole prefix, indent included, so an indented bullet keeps its
        // place and its mark is never sent to be translated.
        final marks = [
          for (final line in lines)
            RegExp(r'^\s*[•*-]\s+').firstMatch(line)?.group(0) ?? '',
        ];
        pieces.addAll([
          for (final (i, line) in lines.indexed)
            line.substring(marks[i].length),
        ]);
        rebuild[spec.id] = (out) => [
          for (final (i, line)
              in out.sublist(start, start + lines.length).indexed)
            lines[i].trim().isEmpty ? '' : '${marks[i]}${line.trim()}',
        ].join('\n');
      }
    }
    if (pieces.isEmpty) return const {};
    final translated = await translator.translate(pieces, from: from, to: to);
    final out = <String, String>{};
    for (final MapEntry(key: id, value: build) in rebuild.entries) {
      var text = build(translated);
      final spec = store.field(id)!;
      if (store.isApple) {
        text = scrubOtherPlatforms(text, mac: store == CopyStore.macAppStore);
      }
      if (spec.keywords) {
        text = packKeywords(
          store.isApple
              ? tidyAppleKeywords(
                  text,
                  name: out['name'] ?? '',
                  subtitle: out['subtitle'] ?? '',
                  appName: appName,
                  mac: store == CopyStore.macAppStore,
                )
              : text,
          spec.limit,
        );
      }
      if (text.trim().isNotEmpty) out[id] = text;
    }
    return out;
  }
}
