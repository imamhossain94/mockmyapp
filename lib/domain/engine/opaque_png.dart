/// A PNG with no alpha channel, from the browser's own encoder.
///
/// Both stores ask for screenshots as a JPEG or a 24-bit PNG — "no alpha" in
/// Google Play's words. The engine only writes 32-bit PNGs, and re-encoding in
/// Dart took seconds a screen in a browser, where there is no isolate to do it
/// on. A canvas made without alpha encodes as plain RGB, natively, in a few
/// milliseconds. Web only, hence the conditional import.
library;

export 'opaque_png_stub.dart'
    if (dart.library.js_interop) 'opaque_png_web.dart';
