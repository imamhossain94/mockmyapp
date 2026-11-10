import 'package:flutter/foundation.dart';

import '../store_copy/store_limits.dart';

/// Everything a listing says in words outside its screenshots — name,
/// subtitle, keywords, descriptions, what's new, screenshot alt text — for
/// each store, in each language.
///
/// Store → locale → field → text. Stores are [CopyStore] names, locales the
/// project's store locale codes, fields the [CopyFieldSpec] ids. Every
/// language is kept under its own code, the default one included: unlike a
/// caption, which holds the default language's words itself and the others as
/// translations, store copy has no "own" language, so changing the project's
/// default moves nothing here.
///
/// A list field — Microsoft's product features, Play's per-screenshot alt
/// text — is one item per line.
///
/// Keys this build does not know (a store or field a newer build added) are
/// kept as they were read and written back untouched, so opening a newer
/// project here loses nothing. Empty text is never kept: clearing a field
/// removes it, a language with no fields left goes, and so does a store, so a
/// project with no copy writes no `storeCopy` at all — which is what keeps
/// every project saved before store copy existed byte for byte.
@immutable
class StoreCopy {
  const StoreCopy._(this._byStore);

  static const empty = StoreCopy._({});

  final Map<String, Map<String, Map<String, String>>> _byStore;

  bool get isEmpty => _byStore.isEmpty;

  /// [field]'s text for [store] in [locale], or an empty string.
  String text(CopyStore store, String locale, String field) =>
      _byStore[store.name]?[locale]?[field] ?? '';

  /// Every field written for [store] in [locale].
  Map<String, String> fieldsOf(CopyStore store, String locale) =>
      Map.unmodifiable(_byStore[store.name]?[locale] ?? const {});

  /// Whether anything is written for [store] — in [locale], when given.
  bool has(CopyStore store, [String? locale]) {
    final locales = _byStore[store.name];
    if (locales == null) return false;
    return locale == null || locales.containsKey(locale);
  }

  /// The stores this build knows that have copy, in [CopyStore] order.
  List<CopyStore> get stores => [
    for (final store in CopyStore.values)
      if (_byStore.containsKey(store.name)) store,
  ];

  /// The locales [store] has copy in, in the order they were written.
  List<String> localesOf(CopyStore store) =>
      List.unmodifiable(_byStore[store.name]?.keys ?? const <String>[]);

  /// Every locale any store has copy in.
  Set<String> get locales => {
    for (final byLocale in _byStore.values) ...byLocale.keys,
  };

  /// This copy with [field] of [store] in [locale] set to [text]; an empty
  /// [text] removes the field.
  StoreCopy withText(
    CopyStore store,
    String locale,
    String field,
    String text,
  ) => withFields(store, locale, {field: text});

  /// This copy with [fields] written for [store] in [locale], over whatever
  /// was there; an empty text removes its field. With [replace], fields not
  /// named in [fields] go too.
  StoreCopy withFields(
    CopyStore store,
    String locale,
    Map<String, String> fields, {
    bool replace = false,
  }) {
    final next = _mutable();
    final byLocale = next.putIfAbsent(store.name, () => {});
    final current = replace ? <String, String>{} : {...?byLocale[locale]};
    for (final MapEntry(:key, :value) in fields.entries) {
      if (value.isEmpty) {
        current.remove(key);
      } else {
        current[key] = value;
      }
    }
    if (current.isEmpty) {
      byLocale.remove(locale);
    } else {
      byLocale[locale] = current;
    }
    if (byLocale.isEmpty) next.remove(store.name);
    return StoreCopy._frozen(next);
  }

  /// This copy without anything for [store] in [locale].
  StoreCopy withoutLocale(CopyStore store, String locale) =>
      withFields(store, locale, const {}, replace: true);

  Map<String, Map<String, Map<String, String>>> _mutable() => {
    for (final MapEntry(key: store, value: byLocale) in _byStore.entries)
      store: {
        for (final MapEntry(key: locale, value: fields) in byLocale.entries)
          locale: {...fields},
      },
  };

  factory StoreCopy._frozen(Map<String, Map<String, Map<String, String>>> m) =>
      m.isEmpty
      ? empty
      : StoreCopy._(
          Map.unmodifiable({
            for (final MapEntry(key: store, value: byLocale) in m.entries)
              store: Map<String, Map<String, String>>.unmodifiable({
                for (final MapEntry(key: locale, value: fields)
                    in byLocale.entries)
                  locale: Map<String, String>.unmodifiable(fields),
              }),
          }),
        );

  /// The saved shape: `{"appStore": {"en-US": {"name": "…"}}}`, in the order
  /// it was written.
  Map<String, dynamic> toJson() => {
    for (final MapEntry(key: store, value: byLocale) in _byStore.entries)
      store: {
        for (final MapEntry(key: locale, value: fields) in byLocale.entries)
          locale: {...fields},
      },
  };

  /// Reads saved copy. Anything that is not text where text belongs is
  /// skipped rather than thrown on; unknown stores and fields are kept.
  factory StoreCopy.fromJson(Object? json) {
    if (json is! Map) return empty;
    final out = <String, Map<String, Map<String, String>>>{};
    for (final MapEntry(key: store, value: byLocale) in json.entries) {
      if (store is! String || byLocale is! Map) continue;
      final locales = <String, Map<String, String>>{};
      for (final MapEntry(key: locale, value: fields) in byLocale.entries) {
        if (locale is! String || fields is! Map) continue;
        final texts = <String, String>{
          for (final MapEntry(key: field, value: text) in fields.entries)
            if (field is String && text is String && text.isNotEmpty)
              field: text,
        };
        if (texts.isNotEmpty) locales[locale] = texts;
      }
      if (locales.isNotEmpty) out[store] = locales;
    }
    return StoreCopy._frozen(out);
  }

  @override
  bool operator ==(Object other) {
    if (other is! StoreCopy) return false;
    if (other._byStore.length != _byStore.length) return false;
    for (final MapEntry(key: store, value: byLocale) in _byStore.entries) {
      final theirs = other._byStore[store];
      if (theirs == null || theirs.length != byLocale.length) return false;
      for (final MapEntry(key: locale, value: fields) in byLocale.entries) {
        final theirFields = theirs[locale];
        if (theirFields == null || !mapEquals(theirFields, fields)) {
          return false;
        }
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered([
    for (final MapEntry(key: store, value: byLocale) in _byStore.entries)
      for (final MapEntry(key: locale, value: fields) in byLocale.entries)
        for (final MapEntry(key: field, value: text) in fields.entries)
          Object.hash(store, locale, field, text),
  ]);
}
