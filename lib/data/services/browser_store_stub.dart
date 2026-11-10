import 'browser_store.dart';

/// Off the web there is a filesystem, and no browser store.
KeyValueStore? createBrowserStore() => null;
