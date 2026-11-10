import 'dart:typed_data';

import 'browser_store_stub.dart'
    if (dart.library.js_interop) 'browser_store_web.dart';

/// Somewhere to keep documents and files where there is no filesystem.
///
/// The web build has no documents directory, so projects, imported pictures
/// and uploaded fonts used to live in memory and vanish on a refresh. In a
/// browser this is IndexedDB; on every other platform it is null and the
/// filesystem is used as before.
///
/// Text for JSON documents, bytes for images and fonts. Every method answers
/// rather than throws — a browser in private mode, or one out of quota, still
/// gets an app it can use; what it loses is persistence.
abstract interface class KeyValueStore {
  Future<String?> readText(String key);
  Future<void> writeText(String key, String value);
  Future<Uint8List?> readBytes(String key);
  Future<void> writeBytes(String key, Uint8List value);
  Future<void> delete(String key);

  /// Every byte entry whose key starts with [prefix], keyed by the rest of the
  /// key.
  Future<Map<String, Uint8List>> readAllBytes(String prefix);
}

/// The browser's store, or null off the web. Assignable so a test can run the
/// web path on the VM with a [MemoryKeyValueStore].
KeyValueStore? browserStore = createBrowserStore();

/// A [KeyValueStore] in memory, for tests.
class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, Object> entries = {};

  @override
  Future<String?> readText(String key) async => entries[key] as String?;

  @override
  Future<void> writeText(String key, String value) async =>
      entries[key] = value;

  @override
  Future<Uint8List?> readBytes(String key) async => entries[key] as Uint8List?;

  @override
  Future<void> writeBytes(String key, Uint8List value) async =>
      entries[key] = value;

  @override
  Future<void> delete(String key) async => entries.remove(key);

  @override
  Future<Map<String, Uint8List>> readAllBytes(String prefix) async => {
    for (final e in entries.entries)
      if (e.key.startsWith(prefix) && e.value is Uint8List)
        e.key.substring(prefix.length): e.value as Uint8List,
  };
}
