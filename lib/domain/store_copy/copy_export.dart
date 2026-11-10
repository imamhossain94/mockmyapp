/// Store copy on its way out of the app: as fastlane's metadata files, inside
/// the fastlane ZIP the export already makes, and as plain text for the
/// clipboard.
library;

import '../../data/repositories/fastlane_layout.dart';
import '../models/locales.dart';
import '../models/store_copy.dart';
import 'copy_lint.dart';
import 'store_limits.dart';

/// `fastlane deliver`'s file for each Apple field
/// (https://docs.fastlane.tools/actions/deliver/).
const kDeliverFiles = {
  'name': 'name.txt',
  'subtitle': 'subtitle.txt',
  'keywords': 'keywords.txt',
  'promotionalText': 'promotional_text.txt',
  'description': 'description.txt',
  'whatsNew': 'release_notes.txt',
};

/// `fastlane supply`'s file for each Play field
/// (https://docs.fastlane.tools/actions/supply/). Release notes go in
/// `changelogs/default.txt`, which supply uses for any version code that has
/// no changelog of its own.
const kSupplyFiles = {
  'title': 'title.txt',
  'shortDescription': 'short_description.txt',
  'fullDescription': 'full_description.txt',
  'releaseNotes': 'changelogs/default.txt',
};

/// Where Mac App Store copy goes: beside deliver's iOS metadata rather than
/// over it, like `screenshots-macos` beside `screenshots`. Point the macOS
/// run's `metadata_path` at it.
const kMacMetadataFolder = 'metadata-macos';

/// One text file of the layout.
typedef FastlaneTextFile = ({String path, String text});

/// Every store-copy file of a fastlane layout for [copy], under
/// [FastlaneLayout.root]:
///
/// * App Store: `fastlane/metadata/<locale>/name.txt` and the rest, in App
///   Store Connect's locale codes (`ja`, `no`…);
/// * Mac App Store: the same under `fastlane/metadata-macos/`;
/// * Google Play: `fastlane/metadata/android/<locale>/title.txt` and the
///   rest, in the Play Console's codes (`zh-CN`, `iw-IL`…).
///
/// Written exactly as typed, with no newline added: deliver uploads the
/// keyword file as it stands, and a trailing newline is a byte Apple counts.
/// Other stores have no fastlane layout, so their copy is left to "Copy all".
List<FastlaneTextFile> fastlaneTextFiles(StoreCopy copy) {
  const root = FastlaneLayout.root;
  final out = <FastlaneTextFile>[];
  for (final store in copy.stores) {
    final (folder, files, localeOf) = switch (store) {
      CopyStore.appStore => (
        'metadata',
        kDeliverFiles,
        FastlaneLayout.appleLocale,
      ),
      CopyStore.macAppStore => (
        kMacMetadataFolder,
        kDeliverFiles,
        FastlaneLayout.appleLocale,
      ),
      CopyStore.playStore => (
        'metadata/android',
        kSupplyFiles,
        FastlaneLayout.playLocale,
      ),
      _ => (null, const <String, String>{}, (String l) => l),
    };
    if (folder == null) continue;
    for (final locale in copy.localesOf(store)) {
      final fields = copy.fieldsOf(store, locale);
      for (final MapEntry(key: id, value: file) in files.entries) {
        final text = fields[id];
        if (text == null || text.trim().isEmpty) continue;
        out.add((path: '$root/$folder/${localeOf(locale)}/$file', text: text));
      }
    }
  }
  return out;
}

/// Whether [copy] has anything a fastlane layout carries.
bool hasFastlaneText(StoreCopy copy) => fastlaneTextFiles(copy).isNotEmpty;

/// The fields of [copy] that go into the fastlane layout over their store's
/// limit — the uploads deliver or supply will refuse until they are
/// shortened — as lines for the export checklist.
List<String> fastlaneOverLimitNotes(StoreCopy copy) => [
  for (final store in copy.stores)
    if (store == CopyStore.appStore ||
        store == CopyStore.macAppStore ||
        store == CopyStore.playStore)
      for (final locale in copy.localesOf(store))
        for (final MapEntry(key: id, value: text)
            in copy.fieldsOf(store, locale).entries)
          if (store.field(id) case final spec?
              when (store.isApple ? kDeliverFiles : kSupplyFiles).containsKey(
                    id,
                  ) &&
                  countField(spec, text).over)
            'Over its limit: ${store.label} · ${localeFor(locale).name} · '
                '${spec.label} (${countField(spec, text).label}). '
                '${store.isApple ? 'deliver' : 'supply'} will refuse it until '
                'it is shortened.',
];

/// [store]'s copy in [locale] as one block of plain text — each field's
/// label over its text, in the console's order — for "Copy all".
String copyAllText(CopyStore store, String locale, Map<String, String> fields) {
  final blocks = [
    '${store.label} · ${localeFor(locale).name}',
    for (final spec in store.allFields)
      if (fields[spec.id] case final text? when text.trim().isNotEmpty)
        '${spec.label}\n$text',
  ];
  return blocks.join('\n\n');
}
