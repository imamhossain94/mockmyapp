import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'browser_store.dart';

KeyValueStore? createBrowserStore() => IndexedDbStore();

/// [KeyValueStore] on IndexedDB: one database, one object store of plain
/// key/value pairs. Strings for documents, `Uint8Array`s for files — both are
/// structured-cloneable, so nothing is encoded on the way in or out.
class IndexedDbStore implements KeyValueStore {
  static const _database = 'mockmyapp';
  static const _objects = 'kv';

  Future<web.IDBDatabase?>? _db;

  Future<web.IDBDatabase?> _open() => _db ??= () async {
    try {
      // Asked once: without it a browser under storage pressure may clear the
      // app's data like any cache. A refusal is fine — it only means "best
      // effort", which is what there was before.
      unawaited(
        web.window.navigator.storage.persist().toDart.then(
          (_) {},
          onError: (_) {},
        ),
      );
      final done = Completer<web.IDBDatabase?>();
      final request = web.window.indexedDB.open(_database, 1);
      request.onupgradeneeded = ((web.Event _) {
        (request.result as web.IDBDatabase).createObjectStore(_objects);
      }).toJS;
      request.onsuccess = ((web.Event _) {
        done.complete(request.result as web.IDBDatabase);
      }).toJS;
      request.onerror = ((web.Event _) => done.complete(null)).toJS;
      request.onblocked = ((web.Event _) => done.complete(null)).toJS;
      return await done.future;
    } catch (_) {
      return null;
    }
  }();

  Future<JSAny?> _await(web.IDBRequest request) {
    final done = Completer<JSAny?>();
    request.onsuccess = ((web.Event _) => done.complete(request.result)).toJS;
    request.onerror = ((web.Event _) => done.complete(null)).toJS;
    return done.future;
  }

  Future<web.IDBObjectStore?> _objectStore(String mode) async {
    final db = await _open();
    if (db == null) return null;
    try {
      return db.transaction(_objects.toJS, mode).objectStore(_objects);
    } catch (_) {
      return null;
    }
  }

  Future<JSAny?> _get(String key) async {
    final store = await _objectStore('readonly');
    if (store == null) return null;
    try {
      return await _await(store.get(key.toJS));
    } catch (_) {
      return null;
    }
  }

  Future<void> _put(String key, JSAny value) async {
    final store = await _objectStore('readwrite');
    if (store == null) return;
    try {
      await _await(store.put(value, key.toJS));
    } catch (_) {}
  }

  @override
  Future<String?> readText(String key) async {
    final value = await _get(key);
    return value.isA<JSString>() ? (value as JSString).toDart : null;
  }

  @override
  Future<void> writeText(String key, String value) => _put(key, value.toJS);

  @override
  Future<Uint8List?> readBytes(String key) async {
    final value = await _get(key);
    return value.isA<JSUint8Array>() ? (value as JSUint8Array).toDart : null;
  }

  @override
  Future<void> writeBytes(String key, Uint8List value) => _put(key, value.toJS);

  @override
  Future<void> delete(String key) async {
    final store = await _objectStore('readwrite');
    if (store == null) return;
    try {
      await _await(store.delete(key.toJS));
    } catch (_) {}
  }

  @override
  Future<Map<String, Uint8List>> readAllBytes(String prefix) async {
    final store = await _objectStore('readonly');
    if (store == null) return const {};
    try {
      // Every key from the prefix up to the prefix followed by the highest
      // code unit: exactly the keys that start with it.
      final range = web.IDBKeyRange.bound(prefix.toJS, '$prefix￿'.toJS);
      final keys = await _await(store.getAllKeys(range));
      final values = await _await(store.getAll(range));
      if (keys == null || values == null) return const {};
      final k = (keys as JSArray<JSAny?>).toDart;
      final v = (values as JSArray<JSAny?>).toDart;
      return {
        for (var i = 0; i < k.length && i < v.length; i++)
          if (k[i].isA<JSString>() && v[i].isA<JSUint8Array>())
            (k[i] as JSString).toDart.substring(prefix.length):
                (v[i] as JSUint8Array).toDart,
      };
    } catch (_) {
      return const {};
    }
  }
}
