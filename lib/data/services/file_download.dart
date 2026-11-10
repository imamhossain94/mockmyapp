/// Handing a file to the user on a platform with no filesystem.
///
/// A browser cannot be told to write to Downloads; it has to be *offered* the
/// bytes and left to save them where its own settings say. That has no
/// equivalent on a device, and the API that does it does not exist off the
/// web — hence the conditional import rather than a runtime `kIsWeb` branch,
/// which would drag `package:web` into every Android and iOS build.
library;

export 'file_download_stub.dart'
    if (dart.library.js_interop) 'file_download_web.dart';
